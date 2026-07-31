#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/VoiceForge.app"

if [[ ! -d "$PROJECT_DIR/.venv" || ! -d "$APP" ]]; then
  echo "尚未安装，正在运行 install.sh..."
  "$PROJECT_DIR/install.sh"
fi

open "$APP"
echo "VoiceForge 已启动。菜单栏出现 🎙 VoiceForge 后即可使用。"
