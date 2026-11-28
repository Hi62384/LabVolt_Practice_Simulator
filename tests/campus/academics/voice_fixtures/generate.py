"""Regenerate public, synthetic spoken fixtures using FFmpeg's CMU Flite filter.

Requires FFmpeg compiled with libflite and the slt voice. This is test-data
preparation only; the game has no Flite dependency or local-TTS fallback.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import wave

ROOT = Path(__file__).resolve().parent
PHRASES = (
    ("remember_nickname", "My project nickname is Copper Comet. Please remember it."),
    ("recall_nickname", "What is my project nickname?"),
    ("technical_question", "What is the difference between voltage and current?"),
)


def main() -> None:
    entries = []
    for name, text in PHRASES:
        path = ROOT / (name + ".wav")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
                        "-i", f"flite=text={text}:voice=slt", "-ac", "1", "-ar", "16000",
                        "-c:a", "pcm_s16le", "-bitexact", "-y", str(path)], check=True)
        with wave.open(str(path), "rb") as stream:
            frames = stream.getnframes()
            pcm = stream.readframes(frames)
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(16000)
            stream.writeframes(pcm)
        entries.append(dict(file=path.name, text=text,
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            duration_seconds=frames / 16000))
    (ROOT / "manifest.json").write_text(json.dumps({
        "source": "Original test phrases synthesized with CMU Flite slt via FFmpeg. No recordings of users.",
        "format": "mono PCM16 WAV, 16000 Hz", "fixtures": entries}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
