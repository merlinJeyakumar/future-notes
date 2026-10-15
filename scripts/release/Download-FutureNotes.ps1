[CmdletBinding()]
param([string]$DestinationRoot = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
# Use the selected shell's inbox utility module even when launched from a
# developer shell whose PSModulePath contains only PowerShell 7 modules.
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$version = '@@VERSION@@'
$expectedManifestHash = '@@MANIFEST_SHA256@@'
if ($version -notmatch '^\d+\.\d+\.\d+$' -or $expectedManifestHash -notmatch '^[a-f0-9]{64}$') {
    throw 'Use the rendered downloader from the GitHub release, not the source template.'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$baseUrl = "https://github.com/merlinJeyakumar/future-notes/releases/download/v$version"
$parent = [IO.Path]::GetFullPath($DestinationRoot)
if (!(Test-Path -LiteralPath $parent -PathType Container)) { throw 'Choose an existing destination folder.' }
$ancestor = Get-Item -LiteralPath $parent -Force
while ($null -ne $ancestor) {
    if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Choose a destination without linked/reparse-point ancestors.' }
    $ancestor = $ancestor.Parent
}
$destination = Join-Path $parent "FutureNotes-$version-windows-x64"
if (Test-Path -LiteralPath $destination) { throw 'Destination already exists; no files were replaced.' }
$stage = Join-Path $parent ('.future-notes-download-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
$manifestPath = Join-Path $stage 'release-manifest.json'
Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/release-manifest.json" -OutFile $manifestPath
if ((Get-Item -LiteralPath $manifestPath).Length -gt 4MB -or
    (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedManifestHash) {
    throw 'Manifest hash/size mismatch. Partial downloads remain in the staging folder.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.version -notlike "$version+*" -or
    $manifest.entryPoint -ne 'FutureNotes.exe' -or $manifest.platform -ne 'windows-x64') { throw 'Unexpected release identity.' }
$seenAssets = @{}
$seenPaths = @{}
foreach ($entry in $manifest.files.PSObject.Properties) {
    $relative = $entry.Name
    $record = $entry.Value
    if ($relative -notmatch '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$' -or
        @($relative.Split('/') | Where-Object { $_ -in @('.', '..', 'UserData', 'settings.json', 'AttachmentCache') -or $_ -like 'note_*' -or $_ -like '.future-notes*' }).Count -gt 0 -or
        $record.asset -cne $relative.Replace('/', '--') -or $record.sha256 -notmatch '^[a-f0-9]{64}$' -or
        $record.bytes -isnot [ValueType] -or $record.bytes -lt 0 -or
        $seenAssets.ContainsKey($record.asset) -or $seenPaths.ContainsKey($relative)) { throw 'Invalid/colliding release path.' }
    if ($relative -notlike 'data/*' -and $relative -notin @('FutureNotes.exe','native_assets.json','RUN-ME.txt','RUNTIMES.txt','THIRD-PARTY-NOTICES.txt') -and $relative -notlike '*.dll') { throw 'Unexpected release file.' }
    $seenAssets[$record.asset] = $true
    $seenPaths[$relative] = $true
    $target = [IO.Path]::GetFullPath((Join-Path $stage $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (!$target.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Release path escaped staging.' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri ($baseUrl + '/' + [Uri]::EscapeDataString($record.asset)) -OutFile $target
    if ((Get-Item -LiteralPath $target).Length -ne $record.bytes -or
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) { throw "Release file failed verification: $relative" }
}
foreach ($required in @('FutureNotes.exe','flutter_windows.dll','libmpv-2.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/icudtl.dat','RUN-ME.txt','RUNTIMES.txt')) {
    if (!$seenPaths.ContainsKey($required)) { throw 'Incomplete release.' }
}
# Both paths are new, fixed children of the reviewed destination. No deletion,
# overwrite, executable launch, registry or execution-policy change is performed.
if (Test-Path -LiteralPath $destination) { throw 'Destination appeared during download.' }
Move-Item -LiteralPath $stage -Destination $destination -ErrorAction Stop
Write-Output "Verified portable release: $destination"
Write-Output 'Open RUN-ME.txt, then launch FutureNotes.exe. Keep the DLLs and data folder together.'
