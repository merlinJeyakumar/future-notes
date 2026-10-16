"""Stage/verify an unpacked Windows release. Build tooling only; stdlib only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct


EXE = "FutureNotes.exe"
MANIFEST = "release-manifest.json"
CRT = {"msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"}
# Windows 10/11 inbox libraries, not DLLs copied from the developer's System32.
WINDOWS_DLLS = set("""
advapi32 avicap32 avrt bcrypt bcryptprimitives cfgmgr32 clbcatq combase comctl32 comdlg32 crypt32
cryptbase cryptsp d2d1 d3d9 d3d11 d3d12 dcomp dinput8 dnsapi dwrite dwmapi dxcore
dxgi gdi32 hid imm32 iphlpapi kernel32 kernelbase mf mfplat mfreadwrite mfuuid
msacm32 msvcp_win msvcrt netapi32 ntdll ole32 oleacc oleaut32 opengl32 powrprof
profapi propsys psapi rpcrt4 secur32 setupapi shell32 shcore shlwapi sspicli
ucrtbase uiautomationcore user32 userenv usp10 uxtheme version winhttp wininet
winmm winspool wintrust wldap32 ws2_32 wtsapi32 dbghelp dbgcore normaliz
""".split())


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def no_link(path):
    if path.is_symlink() or getattr(path.lstat(), "st_file_attributes", 0) & 0x400:
        raise ValueError("Linked/reparse-point release path rejected")


def inventory(root):
    for parent in (root, *root.parents):
        no_link(parent)
    found = {}
    folded = set()
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            entry = Path(directory) / name
            no_link(entry)
            relative = entry.relative_to(root).as_posix()
            # Crash symbols and the name map must never be distributed, even
            # when accidentally nested under otherwise allowed Flutter assets.
            lowered = name.lower()
            if (lowered.endswith((".pdb", ".symbols", ".map", ".map.json", ".dsym")) or
                    "obfuscation-map" in lowered or lowered == ".private-release-symbols"):
                raise ValueError("Private symbols must never enter a release")
            if any(p.lower().startswith(("note_", ".future-notes")) or
                   p.lower() in {"userdata", "settings.json", "attachmentcache"}
                   for p in entry.relative_to(root).parts):
                raise ValueError("User data must never enter a release")
            if relative.casefold() in folded:
                raise ValueError("Case-colliding release paths")
            folded.add(relative.casefold())
            if entry.is_file() and relative != MANIFEST:
                found[relative] = {"bytes": entry.stat().st_size, "sha256": sha256(entry),
                                   "asset": relative.replace("/", "--")}
    assets = [item["asset"].casefold() for item in found.values()]
    if len(assets) != len(set(assets)):
        raise ValueError("Case-colliding release asset names")
    return dict(sorted(found.items()))


def pe_imports(path):
    """Read only bounded PE headers/import names, including delay imports."""
    with path.open("rb") as source:
        size = path.stat().st_size

        def read(offset, length):
            if offset < 0 or length < 0 or offset + length > size:
                raise ValueError("Truncated PE")
            source.seek(offset)
            value = source.read(length)
            if len(value) != length:
                raise ValueError("Short PE read")
            return value

        dos = read(0, 64)
        if dos[:2] != b"MZ":
            raise ValueError("Not a Windows binary")
        start = struct.unpack_from("<I", dos, 60)[0]
        header = read(start, 24)
        if header[:4] != b"PE\0\0":
            raise ValueError("Invalid PE signature")
        machine, count = struct.unpack_from("<HH", header, 4)
        optional_size = struct.unpack_from("<H", header, 20)[0]
        if machine != 0x8664 or not 1 <= count <= 96 or not 240 <= optional_size <= 4096:
            raise ValueError("Release requires bounded x64 PE headers")
        optional = read(start + 24, optional_size)
        if struct.unpack_from("<H", optional)[0] != 0x20B:
            raise ValueError("Release requires PE32+")
        image_base = struct.unpack_from("<Q", optional, 24)[0]
        headers_size = struct.unpack_from("<I", optional, 60)[0]
        directories = struct.unpack_from("<I", optional, 108)[0]
        sections = []
        for index in range(count):
            section = read(start + 24 + optional_size + index * 40, 40)
            sections.append(struct.unpack_from("<IIII", section, 8))

        def offset(rva, length):
            if rva < headers_size and rva + length <= headers_size:
                return rva
            for virtual_size, address, raw_size, raw_offset in sections:
                delta = rva - address
                if 0 <= delta and delta + length <= raw_size:
                    return raw_offset + delta
            raise ValueError("PE import address outside file-backed sections")

        def dll_name(rva):
            value = bytearray()
            for index in range(260):
                byte = read(offset(rva + index, 1), 1)
                if byte == b"\0":
                    name = value.decode("ascii").lower()
                    if not re.fullmatch(r"[a-z0-9_.-]+\.dll", name):
                        raise ValueError("Invalid import name")
                    return name
                value.extend(byte)
            raise ValueError("Unbounded DLL import name")

        imports = set()
        for directory, width in ((1, 20), (13, 32)):
            if directories <= directory:
                continue
            rva, length = struct.unpack_from("<II", optional, 112 + directory * 8)
            if not rva:
                continue
            # PE directory Size covers import names/thunks too, not only the
            # descriptor array. libmpv legitimately exceeds 1024 * 20 bytes.
            if not width <= length <= 32 * 1024 * 1024:
                raise ValueError("Unbounded PE import table")
            for cursor in range(0, min(length - width + 1, 1024 * width), width):
                descriptor = read(offset(rva + cursor, width), width)
                if not any(descriptor):
                    break
                fields = struct.unpack("<" + "I" * (width // 4), descriptor)
                name_rva = fields[3] if directory == 1 else fields[1]
                if directory == 13 and not fields[0] & 1:
                    name_rva -= image_base
                imports.add(dll_name(name_rva))
            else:
                raise ValueError("Unterminated PE import table")
        return sorted(imports)


def validate_payload(root):
    files = inventory(root)
    for required in (EXE, "flutter_windows.dll", "libmpv-2.dll",
                     "data/app.so", "data/icudtl.dat", *sorted(CRT)):
        if required not in files or files[required]["bytes"] == 0:
            raise ValueError("Missing required release payload: " + required)
    if not (root / "data/flutter_assets").is_dir():
        raise ValueError("Missing Flutter assets")
    local_dlls = {name.lower() for name in files if "/" not in name and name.lower().endswith(".dll")}
    imports = {}
    for name in files:
        if not name.lower().endswith((".dll", ".exe")):
            continue
        if "/" in name:
            raise ValueError("Native binary outside the app-local directory")
        imports[name] = pe_imports(root / name)
        for dependency in imports[name]:
            if dependency in local_dlls or dependency.startswith(("api-ms-win-", "ext-ms-win-")):
                continue
            if dependency[:-4] not in WINDOWS_DLLS:
                raise ValueError(f"Unbundled non-Windows dependency: {name} -> {dependency}")
    return files, imports


def stage(source, destination, version, revision, documents=None):
    source, destination = Path(source).absolute(), Path(destination).absolute()
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version) or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Exact version and Git revision required")
    if destination == source or source in destination.parents or destination in source.parents:
        raise ValueError("Release source and destination must be disjoint")
    files, imports = validate_payload(source)
    for parent in destination.parents:
        if parent.exists():
            no_link(parent)
    for name in files:
        if "/" not in name and name not in {EXE, "native_assets.json"} and not name.lower().endswith(".dll"):
            raise ValueError("Unexpected build-root file: " + name)
        if "/" in name and not name.startswith("data/"):
            raise ValueError("Unexpected build-root directory")
    # Fresh destination only. Never replace a previous release or user library.
    destination.mkdir(parents=True, exist_ok=False)
    for name in files:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    if inventory(destination) != files:
        raise ValueError("Source changed or release copy failed verification")
    if documents:
        for name in ("RUN-ME.txt", "RUNTIMES.txt", "THIRD-PARTY-NOTICES.txt"):
            original = Path(documents) / name
            no_link(original)
            shutil.copy2(original, destination / name)
        files = inventory(destination)
    manifest = {"schema": 1, "version": version, "gitRevision": revision,
                "platform": "windows-x64", "minimumOS": "Windows 10",
                "entryPoint": EXE, "files": files, "imports": imports}
    (destination / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    verify(destination)
    return manifest


def verify(root):
    root = Path(root).absolute()
    no_link(root / MANIFEST)
    if (root / MANIFEST).stat().st_size > 4 * 1024 * 1024:
        raise ValueError("Oversized release manifest")
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    if (not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", manifest.get("version", "")) or
            not re.fullmatch(r"[a-f0-9]{40}", manifest.get("gitRevision", "")) or
            manifest.get("platform") != "windows-x64" or manifest.get("entryPoint") != EXE):
        raise ValueError("Invalid release identity")
    files, imports = validate_payload(root)
    if manifest.get("schema") != 1 or files != manifest.get("files") or imports != manifest.get("imports"):
        raise ValueError("Release inventory/hash/import mismatch")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("stage", "verify"))
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--source")
    parser.add_argument("--version")
    parser.add_argument("--revision")
    parser.add_argument("--documents")
    arguments = parser.parse_args()
    try:
        result = (stage(arguments.source, arguments.bundle, arguments.version, arguments.revision,
                        arguments.documents)
                  if arguments.mode == "stage" else verify(arguments.bundle))
        print(json.dumps({"version": result["version"], "gitRevision": result["gitRevision"],
                          "files": len(result["files"]), "verified": True}))
    except (ValueError, OSError, KeyError, TypeError, struct.error) as error:
        parser.exit(1, f"Release validation failed: {error}\n")
