[CmdletBinding()]
param([ValidateSet('Launch', 'Candidate')][string]$Mode = 'Launch')

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$definesPath = Join-Path $workspace '.validation/future-notes-activation-config-20261013/defines.json'
Set-Location -LiteralPath $workspace

function Get-Candidate {
    $files = [Collections.Generic.List[object]]::new()
    foreach ($folder in @('lib', 'test', 'windows/runner', 'scripts/storage')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $workspace $folder) -File -Recurse)) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Linked candidate source is not admitted.'
            }
            $files.Add($file)
        }
    }
    foreach ($relative in @('pubspec.yaml', 'pubspec.lock', '.validation/future-notes-activation-config-20261013/defines.json', '.validation/future-notes-activation-config-20261013/locations.json')) {
        $files.Add((Get-Item -LiteralPath (Join-Path $workspace $relative)))
    }
    $records = foreach ($file in @($files | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($workspace.Length + 1)
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $relative + "`0" + $hash
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes(($records -join "`n")))
        [pscustomobject]@{ digest = ([BitConverter]::ToString($digest)).Replace('-', ''); files = $files.Count }
    } finally {
        $algorithm.Dispose()
    }
}

if ($Mode -eq 'Candidate') {
    Get-Candidate
    return
}

$receiptPath = Join-Path $workspace '.validation/future-notes-activation-config-20261013/passing-tests.json'
if (-not (Test-Path -LiteralPath $receiptPath)) {
    throw 'Required integration tests have not passed; activation is blocked.'
}
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$candidate = Get-Candidate
if ($receipt.version -ne 1 -or $receipt.exitCode -ne 0 -or
    $receipt.scope -cne 'storage-activation-correction' -or
    $receipt.candidate.digest -cne $candidate.digest -or
    $receipt.candidate.files -ne $candidate.files) {
    throw 'Passing tests do not match this candidate; activation is blocked.'
}

# Recheck the original and immutable backup immediately before activation.
& (Join-Path $PSScriptRoot 'Prepare-StorageActivation.ps1') -Mode Verify
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (@(Get-Process -Name flutter_application_1 -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'A project app is running; a second instance will not be launched.'
}
if (-not (Test-Path -LiteralPath $definesPath)) {
    throw 'The reviewed activation configuration is missing.'
}

# One compilation and launch. The previous executable is in the verified backup.
# Paths are supplied from the private local configuration, never committed.
& 'C:\src\flutter\bin\flutter.bat' run -d windows --debug --no-pub --no-hot -t lib/main.dart "--dart-define-from-file=$definesPath"
exit $LASTEXITCODE
