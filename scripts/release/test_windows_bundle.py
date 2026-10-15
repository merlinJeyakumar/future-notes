import json
from pathlib import Path
import struct
import subprocess
import os
import tempfile
import unittest

from windows_bundle import EXE, MANIFEST, CRT, pe_imports, sha256, stage, verify


def binary(imports=(), delay=False, machine=0x8664):
    data = bytearray(2048)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<HH", data, 132, machine, 1)
    struct.pack_into("<H", data, 148, 240)
    optional = 152
    struct.pack_into("<H", data, optional, 0x20B)
    struct.pack_into("<Q", data, optional + 24, 0x140000000)
    struct.pack_into("<I", data, optional + 60, 512)
    struct.pack_into("<I", data, optional + 108, 16)
    struct.pack_into("<IIII", data, optional + 240 + 8, 1536, 4096, 1536, 512)
    if imports:
        width, directory = (32, 13) if delay else (20, 1)
        struct.pack_into("<II", data, optional + 112 + directory * 8, 4096, width * (len(imports) + 1))
        cursor = 1024
        for index, name in enumerate(imports):
            fields = [0] * (width // 4)
            fields[1 if delay else 3] = 4096 + cursor - 512
            if delay:
                fields[0] = 1
            struct.pack_into("<" + "I" * len(fields), data, 512 + index * width, *fields)
            value = name.encode("ascii") + b"\0"
            data[cursor:cursor + len(value)] = value
            cursor += len(value)
    return data


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="future-notes-validation-release-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "Release"
        self.source.mkdir()
        for name in (EXE, "flutter_windows.dll", "libmpv-2.dll", *CRT):
            (self.source / name).write_bytes(binary(["KERNEL32.dll"]))
        (self.source / "data/flutter_assets").mkdir(parents=True)
        for name in ("data/app.so", "data/icudtl.dat", "data/flutter_assets/AssetManifest.bin"):
            (self.source / name).write_bytes(b"synthetic asset")
        self.bundle = self.root / "portable"

    def tearDown(self):
        self.temporary.cleanup()

    def stage(self):
        return stage(self.source, self.bundle, "1.1.0+2", "a" * 40)

    def test_full_round_trip_includes_runtime_and_nested_asset_hashes(self):
        first = self.stage()
        self.assertEqual(verify(self.bundle), first)
        self.assertEqual(first["files"]["data/app.so"]["asset"], "data--app.so")

    def test_missing_crt_never_publishes_folder(self):
        (self.source / "msvcp140.dll").unlink()
        with self.assertRaisesRegex(ValueError, "Missing required"):
            self.stage()
        self.assertFalse(self.bundle.exists())

    def test_unbundled_regular_and_delay_imports_rejected(self):
        for delayed in (False, True):
            with self.subTest(delay=delayed):
                (self.source / EXE).write_bytes(binary(["missing-runtime.dll"], delay=delayed))
                with self.assertRaisesRegex(ValueError, "Unbundled"):
                    self.stage()
                self.assertFalse(self.bundle.exists())

    def test_delay_import_parser_reads_actual_names(self):
        path = self.source / EXE
        path.write_bytes(binary(["VCRUNTIME140.dll", "USER32.dll"], delay=True))
        self.assertEqual(pe_imports(path), ["user32.dll", "vcruntime140.dll"])

    def test_import_directory_size_includes_auxiliary_names_and_thunks(self):
        path = self.source / EXE
        value = binary(["KERNEL32.dll"])
        struct.pack_into("<I", value, 152 + 124, 22980)
        path.write_bytes(value)
        self.assertEqual(pe_imports(path), ["kernel32.dll"])
        struct.pack_into("<I", value, 152 + 124, 32 * 1024 * 1024 + 1)
        path.write_bytes(value)
        with self.assertRaisesRegex(ValueError, "Unbounded"):
            pe_imports(path)

    def test_wrong_architecture_and_truncated_header_rejected(self):
        for value in (binary(machine=0x14C), b"MZ"):
            (self.source / EXE).write_bytes(value)
            with self.assertRaises(ValueError):
                self.stage()

    def test_notes_settings_recovery_and_cache_rejected_before_copy(self):
        for name in ("note_synthetic", "settings.json", ".future-notes-recovery", "AttachmentCache"):
            item = self.source / name
            item.write_bytes(b"unrelated sentinel")
            with self.assertRaisesRegex(ValueError, "User data"):
                self.stage()
            self.assertEqual(item.read_bytes(), b"unrelated sentinel")
            self.assertFalse(self.bundle.exists())
            item.unlink()

    def test_existing_destination_remains_untouched(self):
        self.bundle.mkdir()
        sentinel = self.bundle / "keep.txt"
        sentinel.write_bytes(b"preserve")
        with self.assertRaises(FileExistsError):
            self.stage()
        self.assertEqual(sentinel.read_bytes(), b"preserve")

    def test_tampering_and_extra_files_rejected(self):
        self.stage()
        target = self.bundle / "data/app.so"
        original = target.read_bytes()
        target.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            verify(self.bundle)
        target.write_bytes(original)
        (self.bundle / "extra.txt").write_bytes(b"extra")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            verify(self.bundle)

    def test_unexpected_source_files_and_asset_collisions_rejected(self):
        (self.source / "unreviewed.txt").write_text("unexpected")
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            self.stage()

    def test_manifest_identity_tampering_rejected(self):
        self.stage()
        path = self.bundle / MANIFEST
        value = json.loads(path.read_text())
        value["entryPoint"] = "other.exe"
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, "identity"):
            verify(self.bundle)

    @unittest.skipUnless(os.name == "nt", "Windows PowerShell downloader test")
    def test_windows_powershell_downloader_reconstructs_and_refuses_overwrite(self):
        documents = self.root / "documents"
        documents.mkdir()
        for name in ("RUN-ME.txt", "RUNTIMES.txt", "THIRD-PARTY-NOTICES.txt"):
            (documents / name).write_text("synthetic instructions")
        manifest = stage(self.source, self.bundle, "1.1.0+2", "a" * 40, documents)
        assets = self.root / "assets"
        assets.mkdir()
        import shutil
        for relative, record in manifest["files"].items():
            shutil.copy2(self.bundle / relative, assets / record["asset"])
        shutil.copy2(self.bundle / MANIFEST, assets / MANIFEST)
        template = Path(__file__).with_name("Download-FutureNotes.ps1").read_text()
        downloader = self.root / "download.ps1"
        downloader.write_text(template.replace("@@VERSION@@", "1.1.0").replace(
            "@@MANIFEST_SHA256@@", sha256(assets / MANIFEST)), encoding="utf-8")
        # Mock only HTTPS transfer; execute the actual rendered downloader in
        # inbox Windows PowerShell 5, including path, SHA and publication logic.
        wrapper = self.root / "transfer-fixture.ps1"
        wrapper.write_text('''param($Assets, $Downloader, $Target)
$ErrorActionPreference = 'Stop'
function Invoke-WebRequest {
    param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
    $name = [Uri]::UnescapeDataString(([Uri]$Uri).Segments[-1])
    Copy-Item -LiteralPath (Join-Path $Assets $name) -Destination $OutFile
}
& $Downloader -DestinationRoot $Target
''', encoding="utf-8")
        target = self.root / "downloaded"
        target.mkdir()
        powershell = Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        command = [str(powershell), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(wrapper),
                   "-Assets", str(assets), "-Downloader", str(downloader), "-Target", str(target)]
        first = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        copied = target / "FutureNotes-1.1.0-windows-x64"
        self.assertEqual(verify(copied), manifest)
        second = subprocess.run(command, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(verify(copied), manifest)
        # A changed download never becomes a visible final release folder.
        (assets / "msvcp140.dll").write_bytes(b"corrupt download")
        corrupt_target = self.root / "corrupt-download"
        corrupt_target.mkdir()
        bad = subprocess.run(command[:-1] + [str(corrupt_target)], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(bad.returncode, 0)
        self.assertFalse((corrupt_target / copied.name).exists())


if __name__ == "__main__":
    unittest.main()
