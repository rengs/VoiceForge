#!/usr/bin/env bash
set -euo pipefail

osascript -e 'tell application "VoiceForge" to quit' 2>/dev/null || true
echo "VoiceForge 已退出。"
