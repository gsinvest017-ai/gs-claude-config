"""edge-tts helper for language-tutor.

Plays a TTS clip via Microsoft Edge's online neural voices. Requires:
    pip install edge-tts

Streams audio to a temp .mp3 and plays via the OS default handler.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import sys
import tempfile

try:
    import edge_tts  # type: ignore
except ImportError:
    sys.stderr.write(
        "edge-tts not installed. Run: pip install edge-tts\n"
    )
    sys.exit(2)


async def synth(text: str, voice: str, rate: str, out_path: str) -> None:
    communicate = edge_tts.Communicate(text=text, voice=voice, rate=rate)
    await communicate.save(out_path)


def play(path: str) -> None:
    if sys.platform.startswith("win"):
        # PowerShell SoundPlayer doesn't handle mp3; use winmm via PS instead.
        ps = (
            "Add-Type -AssemblyName presentationCore; "
            "$p = New-Object System.Windows.Media.MediaPlayer; "
            f"$p.Open([Uri]::new('{path}')); "
            "$p.Play(); "
            "while (-not $p.NaturalDuration.HasTimeSpan) { Start-Sleep -Milliseconds 50 }; "
            "Start-Sleep -Seconds ([Math]::Ceiling($p.NaturalDuration.TimeSpan.TotalSeconds) + 1); "
            "$p.Close()"
        )
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            check=False,
        )
    elif sys.platform == "darwin":
        subprocess.run(["afplay", path], check=False)
    else:
        subprocess.run(["mpg123", "-q", path], check=False)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--text", required=True)
    p.add_argument("--voice", required=True)
    p.add_argument("--rate", default="+0%", help="e.g. -20%, +0%, +25%")
    p.add_argument("--keep", action="store_true", help="Keep the mp3 file after playback")
    args = p.parse_args()

    fd, path = tempfile.mkstemp(suffix=".mp3", prefix="langtutor-")
    os.close(fd)
    try:
        asyncio.run(synth(args.text, args.voice, args.rate, path))
        play(path)
    finally:
        if not args.keep:
            try:
                os.remove(path)
            except OSError:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
