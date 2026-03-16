---
allowed-tools:
  - Bash
---

The user wants to toggle text-to-speech on or off. The state file is `~/.config/claude-speak/disabled` — if it exists, TTS is disabled; if absent, TTS is enabled.

Based on the user's argument (which may be empty), do ONE of the following:

- **No argument or "toggle"**: Check if `~/.config/claude-speak/disabled` exists. If it does, remove it (enabling TTS). If it doesn't, create it (disabling TTS). Report the new state.
- **"on"**: Remove `~/.config/claude-speak/disabled` if it exists (use `rm -f`). Report: "TTS enabled."
- **"off"**: Create the file with `mkdir -p ~/.config/claude-speak && touch ~/.config/claude-speak/disabled`. Report: "TTS disabled."
- **"status"**: Check if `~/.config/claude-speak/disabled` exists. Report "TTS is currently **enabled**." or "TTS is currently **disabled**."

Keep your response to a single short sentence.
