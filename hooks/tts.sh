#!/bin/bash
# Claude Code TTS Hook
# Speaks notifications and response summaries via Kokoro TTS.
# Receives hook event JSON on stdin.
# Requires: bash, jq, kokoro-tts (uv tool install kokoro-tts), espeak, ffmpeg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HOME}/.cache/claude-speak"
CONFIG_DIR="${HOME}/.config/claude-speak"

VOICE="${CLAUDE_TTS_VOICE:-am_eric}"
SPEED="${CLAUDE_TTS_SPEED:-1.1}"
KOKORO_SOCK="${CACHE_DIR}/kokoro.sock"
KOKORO_SERVER="${SCRIPT_DIR}/kokoro-server.py"
KOKORO_PYTHON="${HOME}/.local/share/uv/tools/kokoro-tts/bin/python"
KOKORO_LOG="${CACHE_DIR}/kokoro-server.log"

mkdir -p "$CACHE_DIR"

# --- Ensure the Kokoro server is running ---
ensure_server() {
  # Check if socket exists and is connectable
  if [[ -S "$KOKORO_SOCK" ]] && "$KOKORO_PYTHON" -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try: s.connect(sys.argv[1]); s.close()
except: sys.exit(1)
" "$KOKORO_SOCK" 2>/dev/null; then
    return 0
  fi
  # Start the server
  nohup "$KOKORO_PYTHON" "$KOKORO_SERVER" >> "$KOKORO_LOG" 2>&1 &
  disown
  # Wait for socket to appear (up to 10s for model load)
  for i in $(seq 1 20); do
    if [[ -S "$KOKORO_SOCK" ]]; then
      # After socket file appears, verify it's actually accepting connections
      for j in $(seq 1 5); do
        if "$KOKORO_PYTHON" -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try: s.connect(sys.argv[1]); s.close()
except: sys.exit(1)
" "$KOKORO_SOCK" 2>/dev/null; then
          return 0
        fi
        sleep 0.5
      done
      return 1
    fi
    sleep 0.5
  done
  return 1
}

# --- TTS engine ---
speak() {
  local text="$1"
  ensure_server || return 0
  # Send request to server via Unix socket (fire-and-forget in background)
  local payload
  payload="$(jq -cn --arg t "$text" --arg v "$VOICE" --arg s "$SPEED" \
    '{text: $t, voice: $v, speed: ($s | tonumber)}')"
  nohup "$KOKORO_PYTHON" -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall(sys.argv[2].encode())
s.shutdown(socket.SHUT_WR)
s.recv(64)
s.close()
" "$KOKORO_SOCK" "$payload" &>/dev/null &
  disown
}

# --- macOS notification ---
notify() {
  local title="$1"
  local message="$2"
  osascript -e "display notification \"$message\" with title \"$title\"" &>/dev/null &
  disown
}

# --- Helpers ---
strip_markdown() {
  # Remove common markdown formatting for cleaner speech
  perl -0777 -pe 's/```[\s\S]*?```//g' |
  sed -E \
    -e 's/`([^`]+)`/\1/g' \
    -e 's/\*\*([^*]+)\*\*/\1/g' \
    -e 's/\*([^*]+)\*/\1/g' \
    -e 's/^#{1,6} //g' \
    -e 's/\[([^]]+)\]\([^)]+\)/\1/g' \
    -e 's/^[>-] //g' \
    -e 's/\*\*//g' \
    -e 's/\*//g'
}

truncate_to_brief() {
  # Keep first ~200 chars, breaking at sentence boundaries (. ! ?)
  local text="$1"
  # Take first 200 chars
  local short="${text:0:200}"
  # Try to break at the last sentence-ending punctuation
  if [[ "$short" =~ ^(.*[.!?])[[:space:]] ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    # No sentence boundary found — just use the truncated text
    echo "${short}..."
  fi
}

# --- Main ---
input="$(cat)"

event="$(echo "$input" | jq -r '.hook_event_name // empty')"

is_disabled() { [[ -f "${CONFIG_DIR}/disabled" ]]; }

case "$event" in
  Notification)
    is_disabled && exit 0
    message="$(echo "$input" | jq -r '.message // empty')"
    if [[ -n "$message" ]]; then
      notify "Claude Code" "$message"
      speak "$message"
    fi
    ;;
  Stop)
    is_disabled && exit 0
    raw="$(echo "$input" | jq -r '.last_assistant_message // empty')"
    if [[ -n "$raw" ]]; then
      cleaned="$(echo "$raw" | strip_markdown)"
      brief="$(truncate_to_brief "$cleaned")"
      if [[ -n "$brief" ]]; then
        notify "Claude Code" "$brief"
        speak "$brief"
      fi
    fi
    ;;
  SessionEnd)
    pkill -f kokoro-server.py 2>/dev/null || true
    sleep 0.5
    rm -f "$KOKORO_SOCK"
    ;;
esac
