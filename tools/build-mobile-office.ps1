param(
    [string]$AndroidSdk = '',
    [string]$NdkVersion = '28.2.13676358'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $projectRoot '.validation/office-oxide-source'
$outputRoot = Join-Path $projectRoot '.native-deps/office-oxide/android'
# v0.1.15 is an annotated tag (tag object fcdbdc2f...). Pin its peeled commit.
$pinnedCommit = '5d183f4de990de254f32976bf952e548bcd25972'
$windowsHost = $env:OS -eq 'Windows_NT'
if ($windowsHost) {
    $hostTag = 'windows-x86_64'
    $archiveName = 'llvm-ar.exe'
    $compilerSuffix = '-clang.cmd'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX)) {
    # NDK uses this directory name for both Intel and Apple Silicon hosts.
    $hostTag = 'darwin-x86_64'
    $archiveName = 'llvm-ar'
    $compilerSuffix = '-clang'
} elseif ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)) {
    $hostTag = 'linux-x86_64'
    $archiveName = 'llvm-ar'
    $compilerSuffix = '-clang'
} else {
    throw 'This Office Android recipe supports Windows, macOS and Linux NDK hosts.'
}
if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    if ($env:ANDROID_SDK_ROOT) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
    elseif ($env:ANDROID_HOME) { $AndroidSdk = $env:ANDROID_HOME }
    elseif ($windowsHost) { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    elseif ($hostTag -eq 'darwin-x86_64') { $AndroidSdk = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Library/Android/sdk' }
    else { $AndroidSdk = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Android/Sdk' }
}
if (Test-Path -LiteralPath $outputRoot) {
    throw 'Preserve/archive the existing Android Office output before rebuilding; it will not be overwritten.'
}
$toolchain = Join-Path $AndroidSdk "ndk/$NdkVersion/toolchains/llvm/prebuilt/$hostTag/bin"
if (-not (Test-Path -LiteralPath (Join-Path $toolchain $archiveName))) {
    throw "Install the pinned Android NDK $NdkVersion before building Office previews."
}
if (-not (Test-Path -LiteralPath $sourceRoot)) {
    & git clone --depth 1 --branch v0.1.15 https://github.com/yfedoseev/office_oxide.git $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Office source download failed.' }
}
$actualCommit = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($actualCommit -ne $pinnedCommit) { throw 'Office source commit does not match the approved pin.' }
if ((& git -C $sourceRoot status --porcelain).Length -ne 0) { throw 'Office source contains local modifications.' }
$targets = @(
    @{ Rust = 'aarch64-linux-android'; Clang = 'aarch64-linux-android24'; Abi = 'arm64-v8a' },
    @{ Rust = 'armv7-linux-androideabi'; Clang = 'armv7a-linux-androideabi24'; Abi = 'armeabi-v7a' },
    @{ Rust = 'x86_64-linux-android'; Clang = 'x86_64-linux-android24'; Abi = 'x86_64' }
)
$priorFlags = $env:RUSTFLAGS
$priorCc = $env:CC
$priorAr = $env:AR
try {
    $env:RUSTFLAGS = '-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384'
    $env:AR = Join-Path $toolchain $archiveName
    foreach ($target in $targets) {
        & rustup target add $target.Rust
        if ($LASTEXITCODE -ne 0) { throw "Rust target installation failed: $($target.Rust)" }
        $linkerName = 'CARGO_TARGET_' + $target.Rust.Replace('-', '_').ToUpperInvariant() + '_LINKER'
        $linker = Join-Path $toolchain ($target.Clang + $compilerSuffix)
        if (-not (Test-Path -LiteralPath $linker)) { throw "The pinned NDK compiler is missing: $($target.Rust)" }
        $priorLinker = [Environment]::GetEnvironmentVariable($linkerName, 'Process')
        try {
            [Environment]::SetEnvironmentVariable($linkerName, $linker, 'Process')
            $env:CC = $linker
            & cargo build --manifest-path (Join-Path $sourceRoot 'Cargo.toml') --locked --release --no-default-features --lib --target $target.Rust --jobs 4
            if ($LASTEXITCODE -ne 0) { throw "Office native compilation failed: $($target.Abi)" }
            $destination = Join-Path $outputRoot $target.Abi
            New-Item -ItemType Directory -Force $destination | Out-Null
            Copy-Item -LiteralPath (Join-Path $sourceRoot "target/$($target.Rust)/release/liboffice_oxide.so") -Destination $destination
        } finally {
            [Environment]::SetEnvironmentVariable($linkerName, $priorLinker, 'Process')
        }
    }
    $licensesRoot = Join-Path (Split-Path $outputRoot -Parent) 'licenses'
    New-Item -ItemType Directory -Force $licensesRoot | Out-Null
    foreach ($license in @('LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE', 'TRADEMARKS.md')) {
        $licenseSource = Join-Path $sourceRoot $license
        $licenseDestination = Join-Path $licensesRoot $license
        if (Test-Path -LiteralPath $licenseDestination) {
            if ((Get-FileHash -LiteralPath $licenseSource -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $licenseDestination -Algorithm SHA256).Hash) {
                throw 'Existing Office license material differs; preserve it before rebuilding.'
            }
        } else { Copy-Item -LiteralPath $licenseSource -Destination $licenseDestination }
    }
    Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Get-FileHash -Algorithm SHA256
} finally {
    $env:RUSTFLAGS = $priorFlags
    $env:CC = $priorCc
    $env:AR = $priorAr
}
