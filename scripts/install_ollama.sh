#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLLAMA_APP="$HOME/Applications/Ollama.app"
OLLAMA_BIN="$OLLAMA_APP/Contents/Resources/ollama"
STARTED_SERVER=0
OLLAMA_PID=""

cleanup() {
  if [[ "$STARTED_SERVER" == "1" && -n "$OLLAMA_PID" ]]; then
    kill "$OLLAMA_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -x "$OLLAMA_BIN" ]]; then
  DOWNLOAD_DIR="$(mktemp -d /tmp/voiceforge-ollama.XXXXXX)"
  trap 'cleanup; rm -rf "$DOWNLOAD_DIR"' EXIT
  echo "下载官方 Ollama..."
  curl --fail --show-error --location --progress-bar \
    -o "$DOWNLOAD_DIR/Ollama-darwin.zip" \
    https://ollama.com/download/Ollama-darwin.zip
  unzip -q "$DOWNLOAD_DIR/Ollama-darwin.zip" -d "$DOWNLOAD_DIR"
  mkdir -p "$HOME/Applications"
  ditto "$DOWNLOAD_DIR/Ollama.app" "$OLLAMA_APP"
fi

if ! curl --silent --fail http://127.0.0.1:11434/api/tags >/dev/null; then
  mkdir -p "$PROJECT_DIR/data"
  "$OLLAMA_BIN" serve >>"$PROJECT_DIR/data/ollama-install.log" 2>&1 &
  OLLAMA_PID=$!
  STARTED_SERVER=1
  for attempt in {1..30}; do
    if curl --silent --fail http://127.0.0.1:11434/api/tags >/dev/null; then
      break
    fi
    sleep 0.5
  done
fi

if ! curl --silent --fail http://127.0.0.1:11434/api/tags |
    grep -q '"name":"qwen2.5:3b"'; then
  "$OLLAMA_BIN" pull qwen2.5:3b
fi

echo "Ollama 与 qwen2.5:3b 已就绪。"
