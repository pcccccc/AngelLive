#!/usr/bin/env python3
"""Regenerate synthetic HLS fixtures; requires ffmpeg with libx264.

The reference transform is intentionally independent of the Swift implementation.
No network input, recordings, credentials, or platform-specific data are used.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

destination = Path(__file__).resolve().parents[1] / "Shared/AngelLiveDependencies/Tests/Fixtures/MediaTransform"
destination.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="media-transform-fixture-") as directory:
    temporary = Path(directory)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
        "testsrc2=size=160x96:rate=12:duration=2", "-an", "-c:v", "libx264",
        "-preset", "veryfast", "-pix_fmt", "yuv420p", "-g", "6", "-sc_threshold", "0",
        "-f", "hls", "-hls_time", "0.5", "-hls_playlist_type", "vod",
        "-hls_segment_filename", str(temporary / "media-transform-plain-%d.ts"),
        str(temporary / "media-transform-plain.m3u8"),
    ], check=True)
    for source in temporary.glob("*.ts"):
        shutil.copyfile(source, destination / source.name)
        content = bytearray(source.read_bytes())
        for period in range((len(content) + 187) // 188):
            state = 0x12345678 ^ (((period + 1) * 0x9E3779B9) & 0xFFFFFFFF)
            if state == 0:
                state = 0x6D2B79F5
            for index in range(period * 188, min(period * 188 + 16, len(content))):
                state ^= (state << 13) & 0xFFFFFFFF
                state ^= state >> 17
                state ^= (state << 5) & 0xFFFFFFFF
                content[index] ^= (state & 255) or 0xA5
        (destination / source.name.replace("plain", "scrambled").replace(".ts", ".bin")).write_bytes(content)
    playlist = (temporary / "media-transform-plain.m3u8").read_text()
    (destination / "media-transform-plain.m3u8").write_text(playlist)
    (destination / "media-transform-scrambled.m3u8").write_text(playlist.replace("plain", "scrambled").replace(".ts", ".bin"))
    (destination / "media-transform-master.m3u8").write_text(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=160000\nmedia-transform-scrambled.m3u8\n'
    )
