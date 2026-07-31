from __future__ import annotations

from contextlib import asynccontextmanager
from dataclasses import asdict
from typing import Annotated

from fastapi import Body, FastAPI, HTTPException
from pydantic import BaseModel, Field

from backend.runtime import Runtime, create_runtime
from backend.service import ProcessResult


class StopRecordingRequest(BaseModel):
    selected_text: str | None = None


class ProcessTextRequest(BaseModel):
    text: str = Field(min_length=1)
    selected_text: str | None = None


class InjectionRequest(BaseModel):
    text: str
    raw_text: str = ""
    intent: str = "input"
    source: str = "dictation"
    model: str = "unknown"
    application: str = ""


class TermRequest(BaseModel):
    source: str = Field(min_length=1)
    target: str = Field(min_length=1)


def create_app(runtime: Runtime | None = None) -> FastAPI:
    owns_runtime = runtime is None
    active_runtime = runtime or create_runtime()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.runtime = active_runtime
        yield
        if owns_runtime:
            active_runtime.close()

    app = FastAPI(
        title="VoiceForge",
        version="0.1.0",
        description="Local-first Chinese voice input service",
        lifespan=lifespan,
    )
    app.state.runtime = active_runtime

    @app.get("/health")
    def health() -> dict[str, object]:
        return {"ok": True, **active_runtime.service.status()}

    @app.get("/v1/status")
    def status() -> dict[str, object]:
        return active_runtime.service.status()

    @app.post("/v1/recording/start")
    def start_recording() -> dict[str, str]:
        try:
            active_runtime.service.start_recording()
            return {"state": "listening"}
        except RuntimeError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(status_code=500, detail=str(error)) from error

    @app.post("/v1/recording/stop")
    def stop_recording(
        request: Annotated[StopRecordingRequest, Body()],
    ) -> dict[str, object]:
        try:
            return asdict(
                active_runtime.service.stop_and_process(request.selected_text)
            )
        except RuntimeError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(status_code=500, detail=str(error)) from error

    @app.post("/v1/process")
    def process(request: ProcessTextRequest) -> dict[str, object]:
        try:
            return asdict(
                active_runtime.service.process_text(
                    request.text,
                    selected_text=request.selected_text,
                    model="manual",
                )
            )
        except RuntimeError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error

    @app.post("/v1/injection/completed")
    def injection_completed(request: InjectionRequest) -> dict[str, bool]:
        active_runtime.service.record_injection(
            ProcessResult(
                text=request.text,
                raw_text=request.raw_text,
                intent=request.intent,
                source=request.source,
                model=request.model,
            ),
            application=request.application,
        )
        return {"ok": True}

    @app.post("/v1/reset")
    def reset() -> dict[str, str]:
        active_runtime.service.reset_error()
        return {"state": "ready"}

    @app.get("/v1/memory/terms")
    def list_terms() -> dict[str, str]:
        return active_runtime.memory.terms()

    @app.put("/v1/memory/terms")
    def put_term(request: TermRequest) -> dict[str, bool]:
        active_runtime.service.set_term(request.source, request.target)
        return {"ok": True}

    return app


app = create_app()
