#!/usr/bin/env python3
"""Kokoro TTS server — keeps the model loaded for low-latency speech.

Listens on a Unix socket and plays audio directly via sounddevice.
Send JSON: {"text": "Hello", "voice": "af_heart", "speed": 1.1}
"""

import json
import os
import signal
import socket
import sys
import threading

import numpy as np
import sounddevice as sd
from kokoro_tts import Kokoro

SOCKET_PATH = os.path.expanduser("~/.cache/claude-speak/kokoro.sock")
KOKORO_DIR = os.path.expanduser("~/.local/share/kokoro-tts")
MODEL_PATH = os.path.join(KOKORO_DIR, "kokoro-v1.0.onnx")
VOICES_PATH = os.path.join(KOKORO_DIR, "voices-v1.0.bin")


SAMPLE_RATE = 24000  # Kokoro's output sample rate
FADE_SAMPLES = int(SAMPLE_RATE * 0.03)  # 30ms fade


class AudioPlayer:
    """Keeps a persistent audio stream open to avoid hardware pop on open/close."""

    def __init__(self, sample_rate: int):
        self._sr = sample_rate
        self._lock = threading.Lock()
        self._interrupt = threading.Event()
        self._stream = sd.OutputStream(
            samplerate=sample_rate, channels=1, dtype="float32"
        )
        self._stream.start()

    def play(self, samples: np.ndarray):
        """Play audio on the persistent stream, interrupting any current playback."""
        self._interrupt.set()
        with self._lock:
            self._interrupt.clear()
            audio = samples.astype(np.float32)
            # Fade in/out
            if len(audio) > FADE_SAMPLES * 2:
                ramp = np.linspace(0.0, 1.0, FADE_SAMPLES, dtype=np.float32)
                audio[:FADE_SAMPLES] *= ramp
                audio[-FADE_SAMPLES:] *= ramp[::-1]
            # Write in small chunks so we can interrupt quickly
            chunk_size = self._sr // 10  # 100ms chunks
            for i in range(0, len(audio), chunk_size):
                if self._interrupt.is_set():
                    break
                self._stream.write(audio[i : i + chunk_size])


def handle_client(conn: socket.socket, kokoro: Kokoro, player: AudioPlayer):
    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        if not data:
            conn.close()
            return
        req = json.loads(data.decode())
        text = req.get("text", "")
        voice = req.get("voice", "af_heart")
        speed = float(req.get("speed", 1.1))
        if not text:
            conn.sendall(b"ok\n")
            conn.close()
            return
        conn.sendall(b"ok\n")
        conn.close()
        # Generate and play (after responding so hook doesn't block)
        samples, sr = kokoro.create(text, voice=voice, speed=speed, lang="en-us")
        player.play(samples)
    except Exception as e:
        try:
            conn.sendall(f"error: {e}\n".encode())
            conn.close()
        except OSError:
            pass


def main():
    # Ensure cache directory exists
    os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)

    # Clean up stale socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    print("Loading Kokoro model...", flush=True)
    kokoro = Kokoro(MODEL_PATH, VOICES_PATH)
    player = AudioPlayer(SAMPLE_RATE)
    print("Model loaded. Listening on", SOCKET_PATH, flush=True)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(16)

    def shutdown(sig, frame):
        server.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    IDLE_TIMEOUT = 600  # seconds

    server.settimeout(IDLE_TIMEOUT)
    while True:
        try:
            conn, _ = server.accept()
            t = threading.Thread(target=handle_client, args=(conn, kokoro, player), daemon=True)
            t.start()
        except socket.timeout:
            print("Idle timeout, shutting down", flush=True)
            break

    server.close()
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)


if __name__ == "__main__":
    main()
