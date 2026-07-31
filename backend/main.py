from __future__ import annotations

import argparse
import os

import uvicorn

from backend.config import Settings
from backend.doctor import format_checks, run_checks


def cli() -> None:
    parser = argparse.ArgumentParser(prog="voiceforge")
    subcommands = parser.add_subparsers(dest="command")
    subcommands.add_parser("serve", help="启动本地 VoiceForge 服务")
    subcommands.add_parser("doctor", help="检查本机运行环境")
    arguments = parser.parse_args()

    if arguments.command == "doctor":
        checks = run_checks()
        print(format_checks(checks))
        raise SystemExit(0 if all(check.ok for check in checks) else 1)

    settings = Settings.load()
    os.environ.setdefault("VOICEFORGE_PREWARM_MIC", "1")
    uvicorn.run(
        "backend.api:app",
        host=settings.host,
        port=settings.port,
        log_level="info",
    )


if __name__ == "__main__":
    cli()
