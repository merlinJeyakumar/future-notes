[CmdletBinding()]
param(
    [string]$FlutterPath = 'flutter',
    [string]$PythonPath = 'python'
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $workspace
try {
    $versionMatch = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version: (\d+\.\d+\.\d+\+\d+)$'
    if ($null -eq $versionMatch) { throw 'A release version/build number is required.' }
    $version = $versionMatch.Matches[0].Groups[1].Value
    $releaseVersion = $version.Split('+')[0]
    $revision = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Git revision unavailable.' }
    git diff --exit-code HEAD -- lib pubspec.yaml pubspec.lock windows/CMakeLists.txt windows/runner scripts/release
    if ($LASTEXITCODE -ne 0) { throw 'Commit the reviewed release inputs before building.' }
    if (@(Get-Process -Name FutureNotes,flutter_application_1 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close Future Notes normally before building.' }
    $bundle = Join-Path $workspace "build/releases/FutureNotes-$releaseVersion-windows-x64"
    $documents = Join-Path $workspace "build/releases/metadata-$releaseVersion"
    if ((Test-Path -LiteralPath $bundle) -or (Test-Path -LiteralPath $documents)) { throw 'Release output already exists; previous artifacts are never replaced.' }
    & $FlutterPath build windows --release --no-pub -t lib/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'Windows Release build failed.' }
    $source = Join-Path $workspace 'build/windows/x64/runner/Release'
    $info = (Get-Item -LiteralPath (Join-Path $source 'FutureNotes.exe')).VersionInfo
    if ($info.ProductVersion -ne $version -or $info.OriginalFilename -ne 'FutureNotes.exe') { throw 'Executable version/name mismatch.' }
    New-Item -ItemType Directory -Path $documents | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') -Destination (Join-Path $documents 'RUN-ME.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY-NOTICES.txt') -Destination $documents
    $flutterInfo = & $FlutterPath --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Flutter version unavailable.' }
    $runtimeText = @("Future Notes $version - included Windows x64 runtimes", '', 'No separate runtime installation is required on Windows 10 (1809+) / Windows 11 x64.',
      "Flutter framework: $($flutterInfo.frameworkVersion)", "Flutter engine revision: $($flutterInfo.engineRevision)", "Dart SDK (AOT build): $($flutterInfo.dartSdkVersion)",
      '',
      'Included native files (embedded file/product versions; exact bytes pinned in release-manifest.json):')
    $lockText = Get-Content -LiteralPath 'pubspec.lock' -Raw
    foreach ($package in @('media_kit','media_kit_video','media_kit_libs_video','media_kit_libs_windows_video')) {
        $packageVersion = [regex]::Match($lockText, '(?ms)^  ' + $package + ':\r?\n.*?^    version: "([^"\r\n]+)"')
        if (!$packageVersion.Success) { throw "Missing pinned native package: $package" }
        $runtimeText += "$package`: $($packageVersion.Groups[1].Value)"
    }
    foreach ($dll in @(Get-ChildItem -LiteralPath $source -Filter '*.dll' -File | Sort-Object Name)) {
        $fileVersion = $dll.VersionInfo.FileVersion
        if ([string]::IsNullOrWhiteSpace($fileVersion)) { $fileVersion = 'not embedded; use manifest SHA-256' }
        $runtimeText += "$($dll.Name): $fileVersion"
    }
    $runtimeText += @('', 'The Universal CRT, Windows APIs and graphics/audio drivers are Windows components, not copied from this developer PC.',
      'Visual C++ DLLs are copied unmodified from Visual Studio Release redistributables, never from Debug or System32.',
      'Do not rename DLLs. Distribute the whole folder. Application-local runtime updates are shipped with future releases.',
      'The app is unsigned. Clean second-PC playback/driver/workflow acceptance remains separate from bundle verification.')
    [IO.File]::WriteAllText((Join-Path $documents 'RUNTIMES.txt'), ($runtimeText -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
    & $PythonPath (Join-Path $PSScriptRoot 'windows_bundle.py') stage --source $source --bundle $bundle --version $version --revision $revision --documents $documents
    if ($LASTEXITCODE -ne 0) { throw 'Portable bundle verification failed.' }
    $manifestHash = (Get-FileHash -LiteralPath (Join-Path $bundle 'release-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $downloader = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Download-FutureNotes.ps1') -Raw).Replace('@@VERSION@@', $releaseVersion).Replace('@@MANIFEST_SHA256@@', $manifestHash)
    [IO.File]::WriteAllText((Join-Path $documents 'Download-FutureNotes.ps1'), $downloader, [Text.UTF8Encoding]::new($false))
    Write-Output "Portable release ready: $bundle"
} finally { Pop-Location }
