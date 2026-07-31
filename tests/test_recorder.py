from time import monotonic

import numpy as np
import pytest

from backend.voice.recorder import AudioRecorder


class FakeStream:
    def stop(self) -> None:
        pass

    def close(self) -> None:
        pass


def recorder_with_samples(tmp_path, samples: np.ndarray) -> AudioRecorder:
    recorder = AudioRecorder(tmp_path, target_sample_rate=16_000)
    recorder._stream = FakeStream()  # type: ignore[assignment]
    recorder._chunks = [samples.astype(np.float32)]
    recorder._input_sample_rate = 16_000
    recorder._input_device_name = "测试麦克风"
    recorder._started_at = monotonic() - 2
    return recorder


def test_reports_recording_that_is_too_short(tmp_path) -> None:
    samples = np.full(3_200, 0.1, dtype=np.float32)
    recorder = recorder_with_samples(tmp_path, samples)

    with pytest.raises(RuntimeError, match=r"录音时间过短（0\.2 秒）"):
        recorder.stop()


def test_reports_recording_volume_that_is_too_low(tmp_path) -> None:
    samples = np.full(16_000, 0.001, dtype=np.float32)
    recorder = recorder_with_samples(tmp_path, samples)

    with pytest.raises(
        RuntimeError,
        match=r"录音音量过低.*输入设备：测试麦克风",
    ):
        recorder.stop()


def test_accepts_audible_recording(tmp_path) -> None:
    positions = np.arange(16_000, dtype=np.float32)
    samples = 0.05 * np.sin(2 * np.pi * 440 * positions / 16_000)
    recorder = recorder_with_samples(tmp_path, samples)

    recording = recorder.stop()

    assert recording.exists()
    assert recording.stat().st_size > 32_000
