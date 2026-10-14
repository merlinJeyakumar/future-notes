"""Independent ZIP64 reader for explicitly disposable streaming fixtures."""
import hashlib
import json
import pathlib
import sys
import zipfile


def digest(stream):
    value = hashlib.sha256()
    count = 0
    while chunk := stream.read(1024 * 1024):
        value.update(chunk)
        count += len(chunk)
    return value.hexdigest(), count


root = pathlib.Path(sys.argv[1]).resolve(strict=True)
if not root.name.startswith("future-notes-validation-"):
    raise ValueError("Explicit disposable fixture root required")
with (root / "results.json").open(encoding="utf-8") as stream:
    results = json.load(stream)
large = next(item for item in results if item["length"] == 10 * 1024**3)
with zipfile.ZipFile(root / "independent-zip64.zip") as archive:
    entries = archive.infolist()
    if len(entries) != 3:
        raise ValueError("Unexpected ZIP entries")
    entry = archive.getinfo("attachments/large/large.bin")
    if entry.file_size != large["cipherLength"] or entry.file_size <= 0xFFFFFFFF:
        raise ValueError("ZIP64 size mismatch")
    with archive.open(entry) as stream:
        actual_hash, count = digest(stream)  # Complete read also validates CRC.
with (root / str(large["length"]) / "synthetic.med").open("rb") as stream:
    expected_hash, expected_count = digest(stream)
if actual_hash != expected_hash or count != expected_count:
    raise ValueError("Independent ZIP64 payload mismatch")
result = {"reader": "Python zipfile", "bytes": count, "sha256": actual_hash,
          "crcValidated": True, "window": 1024 * 1024}
with (root / "independent-reader-result.json").open("w", encoding="utf-8") as stream:
    json.dump(result, stream)
print(json.dumps(result))
