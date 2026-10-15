[CmdletBinding()]
param([string]$DestinationRoot = (Get-Location).Path, [securestring]$GitHubToken)
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
$apiRoot = 'https://api.github.com/repos/merlinJeyakumar/future-notes'
$headers = @{ Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28' }
$token = $env:GH_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:GITHUB_TOKEN }
if ($null -ne $GitHubToken) { $token = [Net.NetworkCredential]::new('', $GitHubToken).Password }
if (![string]::IsNullOrWhiteSpace($token)) { $headers.Authorization = "Bearer $token" }
try {
    $release = Invoke-RestMethod -Uri "$apiRoot/releases/tags/v$version" -Headers $headers
} catch {
    if (![string]::IsNullOrWhiteSpace($token)) { throw 'Release access failed. Check the token account/repository access.' }
    Write-Output 'This release may be private. A GitHub token with access is required only to download; the app itself works offline.'
    $secret = Read-Host 'GitHub token (hidden; not saved)' -AsSecureString
    $token = [Net.NetworkCredential]::new('', $secret).Password
    $headers.Authorization = "Bearer $token"
    try { $release = Invoke-RestMethod -Uri "$apiRoot/releases/tags/v$version" -Headers $headers }
    catch { throw 'Release access failed. No credentials were saved.' }
}
if ($release.tag_name -ne "v$version" -or $release.draft) { throw 'Unexpected/unpublished release.' }
$releaseAssets = @{}
foreach ($asset in $release.assets) {
    if ($releaseAssets.ContainsKey($asset.name) -or $asset.id -isnot [ValueType] -or $asset.id -le 0) { throw 'Invalid release asset inventory.' }
    $releaseAssets[$asset.name] = $asset.id
}
function Receive-ReleaseFile([string]$Name, [string]$Target) {
    if (!$releaseAssets.ContainsKey($Name)) { throw "Missing release asset: $Name" }
    $downloadHeaders = @{ Accept='application/octet-stream'; 'X-GitHub-Api-Version'='2022-11-28' }
    if ($headers.ContainsKey('Authorization')) { $downloadHeaders.Authorization = $headers.Authorization }
    # Credentials go only to this repository's GitHub API. HttpWebRequest strips
    # Authorization when following the signed cross-host asset redirect.
    Invoke-WebRequest -UseBasicParsing -Uri "$apiRoot/releases/assets/$($releaseAssets[$Name])" -Headers $downloadHeaders -OutFile $Target
}
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
Receive-ReleaseFile 'release-manifest.json' $manifestPath
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
    Receive-ReleaseFile $record.asset $target
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
