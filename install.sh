#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
APP_SUPPORT_DIR="$HOME/Library/Application Support/VoiceForge"

choose_python() {
  local candidate
  for candidate in python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done
  echo "需要 Python 3.10–3.12。请先运行：brew install python@3.12" >&2
  exit 1
}

PYTHON_BIN="$(choose_python)"
echo "使用 $("$PYTHON_BIN" --version)"

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install -e "$PROJECT_DIR[asr,test]"

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
fi

mkdir -p "$PROJECT_DIR/data" "$APP_SUPPORT_DIR"
printf '%s\n' "$PROJECT_DIR" > "$APP_SUPPORT_DIR/project-root"

if [[ "${VOICEFORGE_SKIP_MODEL_DOWNLOAD:-0}" != "1" ]]; then
  "$VENV_DIR/bin/python" "$PROJECT_DIR/scripts/download_model.py" \
    --model sensevoice
fi

if [[ "${VOICEFORGE_SKIP_LLM_INSTALL:-0}" != "1" ]]; then
  "$PROJECT_DIR/scripts/install_ollama.sh"
fi

"$PROJECT_DIR/scripts/build_app.sh"
"$VENV_DIR/bin/python" -m pytest

echo
echo "安装完成。"
echo "1. 运行：$PROJECT_DIR/start.sh"
echo "2. 首次启动时允许麦克风和辅助功能权限。"
echo "3. 在任意输入框按住 ⌘⇧Space 讲话，松开后自动输入。"
