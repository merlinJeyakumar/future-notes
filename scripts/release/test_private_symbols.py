import os
from pathlib import Path
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.name == "nt", "Windows ACL test")
class PrivateSymbolsTests(unittest.TestCase):
    def test_fresh_private_directories_acl_and_missing_symbols_fail_closed(self):
        helper = Path(__file__).with_name("Private-ReleaseSymbols.ps1").resolve()
        with tempfile.TemporaryDirectory(prefix="future-notes-validation-symbols-") as temporary:
            root = Path(temporary)
            script = root / "check.ps1"
            script.write_text(r'''
param($Helper, $Workspace)
$ErrorActionPreference = 'Stop'
. $Helper
$first = New-PrivateReleaseSymbols -Workspace $Workspace -Version '1.2.0+3' -Revision ('a' * 40)
$second = New-PrivateReleaseSymbols -Workspace $Workspace -Version '1.2.0+3' -Revision ('a' * 40)
if ($first -eq $second) { throw 'Symbols directory reused.' }
$privateRoot = Join-Path $Workspace '.private-release-symbols'
$acl = Get-Acl -LiteralPath $privateRoot
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
if (!$acl.AreAccessRulesProtected -or $rules.Count -ne 2) { throw 'Private ACL not protected.' }
foreach ($rule in $rules) {
    if ($rule.IdentityReference.Value -notin @($sid, 'S-1-5-18') -or $rule.AccessControlType -ne 'Allow') { throw 'Unexpected private ACL principal.' }
}
$childRules = @((Get-Acl -LiteralPath $first).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
if ($childRules.Count -ne 2) { throw 'Private ACL not inherited by build directory.' }
$rejected = $false
try { Assert-PrivateReleaseSymbols -Directory $first } catch { $rejected = $true }
if (!$rejected) { throw 'Missing symbols accepted.' }
[IO.File]::WriteAllText((Join-Path $first 'app.windows-x64.symbols'), 'synthetic symbols')
[IO.File]::WriteAllText((Join-Path $first 'obfuscation-map.json'), '["Original","a"]')
Assert-PrivateReleaseSymbols -Directory $first
[IO.File]::WriteAllText((Join-Path $first 'obfuscation-map.json'), '["unpaired"]')
$rejected = $false
try { Assert-PrivateReleaseSymbols -Directory $first } catch { $rejected = $true }
if (!$rejected) { throw 'Malformed map accepted.' }
$rejected = $false
try { New-PrivateReleaseSymbols -Workspace $Workspace -Version '../escape' -Revision ('a' * 40) } catch { $rejected = $true }
if (!$rejected) { throw 'Invalid identity accepted.' }
Write-Output 'PASS: private ACL, fresh paths, identity and symbols validation'
''', encoding="utf-8")
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script),
                 "-Helper", str(helper), "-Workspace", str(root)],
                capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
