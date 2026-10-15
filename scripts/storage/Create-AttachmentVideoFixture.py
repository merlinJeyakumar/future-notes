"""Generate a deterministic >8 MiB AVI for manual attachment playback checks."""
import argparse
from pathlib import Path
import struct


def chunk(name, data):
    return name + struct.pack('<I', len(data)) + data + (b'\0' if len(data) % 2 else b'')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination')
    target = Path(parser.parse_args().destination)
    if not target.is_absolute() or not any(p.name.startswith('future-notes-validation-') for p in target.parents):
        raise SystemExit('Explicit disposable validation destination required.')
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() or any(p.is_symlink() for p in target.parents):
        raise SystemExit('Unexpected or linked destination.')
    width, height, frames, fps = 320, 240, 40, 10
    frame_bytes = width * height * 3
    avih = struct.pack('<14I', 1000000 // fps, frame_bytes * fps, 0, 0x10, frames, 0, 1, frame_bytes, width, height, 0, 0, 0, 0)
    strh = struct.pack('<4s4sIHH8I4h', b'vids', b'DIB ', 0, 0, 0, 0, 1, fps, 0, frames, frame_bytes, 0xFFFFFFFF, 0, 0, 0, width, height)
    strf = struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0, frame_bytes, 0, 0, 0, 0)
    hdrl = chunk(b'LIST', b'hdrl' + chunk(b'avih', avih) + chunk(b'LIST', b'strl' + chunk(b'strh', strh) + chunk(b'strf', strf)))
    movi_bytes = 4 + frames * (8 + frame_bytes)
    index = b''.join(struct.pack('<4sIII', b'00db', 0x10, 4 + i * (8 + frame_bytes), frame_bytes) for i in range(frames))
    idx = chunk(b'idx1', index)
    with target.open('xb') as output:
        output.write(b'RIFF' + struct.pack('<I', 4 + len(hdrl) + 8 + movi_bytes + len(idx)) + b'AVI ')
        output.write(hdrl)
        output.write(b'LIST' + struct.pack('<I', movi_bytes) + b'movi')
        for i in range(frames):
            pixel = bytes((i * 6 % 256, 64, 255 - i * 6 % 256))
            output.write(chunk(b'00db', pixel * (width * height)))
        output.write(idx)
    if target.stat().st_size <= 8 * 1024 * 1024:
        raise SystemExit('Fixture size boundary not reached.')
    print(f'Synthetic AVI: {target.stat().st_size} bytes; {frames} frames; {width}x{height}.')


if __name__ == '__main__':
    main()
