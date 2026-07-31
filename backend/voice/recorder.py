from __future__ import annotations

import wave
from pathlib import Path
from threading import Lock
from time import monotonic, sleep, time
from typing import Any

import numpy as np
import sounddevice as sd


class AudioRecorder:
    def __init__(
        self,
        recordings_dir: Path,
        target_sample_rate: int = 16_000,
        device: int | str | None = None,
    ) -> None:
        self._recordings_dir = recordings_dir
        self._target_sample_rate = target_sample_rate
        self._device = device
        self._stream: Any | None = None
        self._chunks: list[np.ndarray] = []
        self._input_sample_rate = target_sample_rate
        self._lock = Lock()
        self._started_at = 0.0

    @property
    def is_recording(self) -> bool:
        return self._stream is not None

    def warm_up(self) -> None:
        """Pay the one-time CoreAudio startup cost before the first hotkey."""
        with self._lock:
            if self._stream is not None:
                return
            device_info = sd.query_devices(self._device, "input")
            sample_rate = int(device_info["default_samplerate"])
            stream = sd.InputStream(
                device=self._device,
                channels=1,
                samplerate=sample_rate,
                dtype="float32",
                callback=lambda *_: None,
            )
            try:
                stream.start()
                sleep(0.1)
            finally:
                stream.stop()
                stream.close()

    def start(self) -> None:
        with self._lock:
            if self._stream is not None:
                raise RuntimeError("已经在录音。")
            device_info = sd.query_devices(self._device, "input")
            self._input_sample_rate = int(device_info["default_samplerate"])
            self._chunks = []
            self._stream = sd.InputStream(
                device=self._device,
                channels=1,
                samplerate=self._input_sample_rate,
                dtype="float32",
                callback=self._audio_callback,
            )
            try:
                self._stream.start()
                self._started_at = monotonic()
            except Exception:
                self._stream.close()
                self._stream = None
                raise

    def _audio_callback(
        self, indata: np.ndarray, frames: int, timing: Any, status: Any
    ) -> None:
        del frames, timing
        if status:
            # PortAudio status flags are advisory. Retain captured frames.
            pass
        self._chunks.append(indata[:, 0].copy())

    def stop(self) -> Path:
        with self._lock:
            if self._stream is None:
                raise RuntimeError("当前没有录音。")
            stream = self._stream
            self._stream = None
            remaining = 0.25 - (monotonic() - self._started_at)
            if remaining > 0:
                sleep(remaining)
            stream.stop()
            stream.close()
            chunks = self._chunks
            self._chunks = []

        if not chunks:
            raise RuntimeError("没有采集到音频，请检查麦克风权限。")
        samples = np.concatenate(chunks)
        samples = self._resample(samples, self._input_sample_rate)
        peak = float(np.max(np.abs(samples))) if samples.size else 0.0
        if peak < 0.001:
            raise RuntimeError("录音几乎没有声音，请检查输入设备。")

        self._recordings_dir.mkdir(parents=True, exist_ok=True)
        path = self._recordings_dir / f"recording-{int(time() * 1000)}.wav"
        pcm = np.clip(samples * 32767, -32768, 32767).astype("<i2")
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(self._target_sample_rate)
            output.writeframes(pcm.tobytes())
        return path

    def _resample(self, samples: np.ndarray, source_rate: int) -> np.ndarray:
        if source_rate == self._target_sample_rate:
            return samples
        source_positions = np.arange(samples.size)
        target_length = round(
            samples.size * self._target_sample_rate / source_rate
        )
        target_positions = np.linspace(
            0, max(samples.size - 1, 0), target_length
        )
        return np.interp(target_positions, source_positions, samples).astype(
            np.float32
        )
