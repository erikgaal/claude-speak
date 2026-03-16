# claude-speak

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that adds text-to-speech to Claude's responses using [Kokoro TTS](https://github.com/hexgrad/kokoro).

When enabled, Claude will speak notifications and response summaries aloud via a persistent local TTS server.

## Prerequisites

- macOS (uses `osascript` for notifications, `sounddevice` for audio playback)
- [uv](https://github.com/astral-sh/uv)
- [espeak-ng](https://github.com/espeak-ng/espeak-ng) — `brew install espeak`
- [ffmpeg](https://ffmpeg.org/) — `brew install ffmpeg`
- Kokoro TTS model files in `~/.local/share/kokoro-tts/`:
  - `kokoro-v1.0.onnx`
  - `voices-v1.0.bin`

## Installation

1. Install the Kokoro TTS tool:

   ```sh
   uv tool install kokoro-tts
   ```

2. Download model files to `~/.local/share/kokoro-tts/`:

   ```sh
   mkdir -p ~/.local/share/kokoro-tts
   # Download kokoro-v1.0.onnx and voices-v1.0.bin from:
   # https://github.com/hexgrad/kokoro/releases
   ```

3. Add the plugin to your Claude Code project or global settings:

   ```sh
   claude plugins add /path/to/claude-speak
   ```

## Configuration

Environment variables:

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_TTS_VOICE` | `am_eric` | Kokoro voice ID |
| `CLAUDE_TTS_SPEED` | `1.1` | Speech speed multiplier |

## Usage

### `/speak` command

Toggle TTS on or off during a session:

```
/speak          # Toggle on/off
/speak on       # Enable TTS
/speak off      # Disable TTS
/speak status   # Show current state
```

### How it works

The plugin registers hooks for three Claude Code events:

- **Notification** — Speaks notification messages
- **Stop** — Speaks a brief summary of Claude's response (first ~200 chars, stripped of markdown)
- **SessionEnd** — Cleans up the TTS server process

On first speech request, the hook starts a persistent Kokoro TTS server that keeps the model loaded in memory for low-latency synthesis. The server automatically shuts down after 10 minutes of inactivity.

### File locations

| Path | Purpose |
|---|---|
| `~/.cache/claude-speak/kokoro.sock` | Unix socket for TTS server |
| `~/.cache/claude-speak/kokoro-server.log` | Server log file |
| `~/.config/claude-speak/disabled` | Sentinel file (exists = TTS disabled) |
