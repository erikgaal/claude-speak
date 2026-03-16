# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-speak is a Claude Code plugin that adds text-to-speech via the Kokoro TTS engine. It speaks notification messages and summaries of Claude's responses (~200 chars). macOS only.

## Architecture

```
Claude Code Events → hooks.json → tts.sh → kokoro-server.py → Audio Output
```

- **hooks/hooks.json** — Registers three Claude Code hook events: `Notification`, `Stop`, `SessionEnd`
- **hooks/tts.sh** — Bash orchestrator that manages server lifecycle, processes text (strips markdown, truncates), sends speak requests via Unix socket, handles cleanup
- **hooks/kokoro-server.py** — Persistent Python daemon that loads the Kokoro TTS model once, listens on a Unix socket (`~/.cache/claude-speak/kokoro.sock`), plays audio via `sounddevice`, auto-shuts down after 10 min idle
- **commands/speak.md** — `/speak` command spec (toggle/on/off/status) using state file `~/.config/claude-speak/disabled`
- **.claude-plugin/plugin.json** — Plugin metadata

## Dependencies

Requires: `kokoro-tts` (via uv), `espeak-ng`, `ffmpeg`, `jq` (all via brew). Python deps: `kokoro_tts`, `sounddevice`, `numpy`.

## Development

No build system, tests, or linting. The plugin is shell scripts + a Python server. To install locally:

```sh
uv tool install kokoro-tts
brew install espeak-ng ffmpeg jq
claude plugins add /path/to/claude-speak
```

## Key Design Decisions

- Fire-and-forget async TTS requests to avoid blocking Claude Code
- Persistent daemon with Unix socket IPC for low-latency repeated requests
- Simple sentinel file (`~/.config/claude-speak/disabled`) for enable/disable state
- Graceful degradation: plugin exits silently if server is unavailable
