[CmdletBinding()]
param([string]$PythonPath = 'python', [string]$GitHubPath = 'gh')
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location $workspace
try {
    if ((git branch --show-current).Trim() -ne 'development') { throw 'Promotion must start from reviewed development.' }
    git diff --exit-code HEAD -- lib pubspec.yaml pubspec.lock windows/CMakeLists.txt windows/runner scripts/release
    if ($LASTEXITCODE -ne 0) { throw 'Release inputs changed after build.' }
    $versionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version: (\d+\.\d+\.\d+)\+(\d+)$'
    $version = $versionLine.Matches[0].Groups[1].Value
    $tag = "v$version"
    $revision = (git rev-parse HEAD).Trim()
    $bundle = Join-Path $workspace "build/releases/FutureNotes-$version-windows-x64"
    $metadata = Join-Path $workspace "build/releases/metadata-$version"
    & $PythonPath (Join-Path $PSScriptRoot 'windows_bundle.py') verify --bundle $bundle
    if ($LASTEXITCODE -ne 0) { throw 'Release bundle verification failed.' }
    $manifest = Get-Content -LiteralPath (Join-Path $bundle 'release-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.version -ne "$version+$($versionLine.Matches[0].Groups[2].Value)") { throw 'Bundle version mismatch.' }
    # A publisher-only correction need not rebuild unchanged app/package inputs.
    # Retain the actual build revision in the manifest and require ancestry plus
    # identical runtime, package construction and distributed text inputs.
    git merge-base --is-ancestor $manifest.gitRevision $revision
    if ($LASTEXITCODE -ne 0) { throw 'Build revision is not an ancestor of the reviewed tag.' }
    git diff --exit-code $manifest.gitRevision $revision -- lib pubspec.yaml pubspec.lock windows/CMakeLists.txt windows/runner scripts/release/windows_bundle.py scripts/release/New-WindowsRelease.ps1 scripts/release/Download-FutureNotes.ps1 scripts/release/README.txt scripts/release/THIRD-PARTY-NOTICES.txt scripts/release/RELEASE_NOTES.md
    if ($LASTEXITCODE -ne 0) { throw 'Runtime/package inputs changed after build.' }
    $oldLocalTag = (git rev-parse refs/tags/v1.0.0).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Existing local release tag could not be verified.' }
    $oldTag = @(git ls-remote --tags origin 'refs/tags/v1.0.0*')
    if ($LASTEXITCODE -ne 0) { throw 'Existing remote release tags could not be verified.' }
    git show-ref --verify --quiet "refs/tags/$tag"
    if ($LASTEXITCODE -eq 0) { throw 'New tag already exists; existing tags are never moved.' }
    $remoteTag = @(git ls-remote --tags origin "refs/tags/$tag")
    if ($LASTEXITCODE -ne 0 -or $remoteTag.Count -ne 0) { throw 'Remote new-tag admission failed.' }
    $assets = Join-Path $workspace "build/releases/assets-$version"
    if (Test-Path -LiteralPath $assets) { throw 'Publication assets already exist; inspect instead of overwriting.' }
    New-Item -ItemType Directory -Path $assets | Out-Null
    foreach ($entry in $manifest.files.PSObject.Properties) {
        Copy-Item -LiteralPath (Join-Path $bundle $entry.Name) -Destination (Join-Path $assets $entry.Value.asset)
    }
    Copy-Item -LiteralPath (Join-Path $bundle 'release-manifest.json') -Destination $assets
    Copy-Item -LiteralPath (Join-Path $metadata 'Download-FutureNotes.ps1') -Destination $assets
    $sumLines = @(Get-ChildItem -LiteralPath $assets -File | Sort-Object Name | ForEach-Object {
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name
    })
    [IO.File]::WriteAllText((Join-Path $assets 'SHA256SUMS.txt'), ($sumLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    git tag -a $tag -m "Future Notes $version Windows x64 portable release"
    if ($LASTEXITCODE -ne 0) { throw 'New annotated tag creation failed.' }
    git push --atomic origin HEAD:refs/heads/development "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0) { throw 'Atomic branch/tag push failed; local tag retained for inspection.' }
    & $GitHubPath release create $tag --repo merlinJeyakumar/future-notes --verify-tag --draft --title "Future Notes $version - Windows portable" --notes-file (Join-Path $PSScriptRoot 'RELEASE_NOTES.md')
    if ($LASTEXITCODE -ne 0) { throw 'Draft release creation failed; no assets were published.' }
    $assetFiles = @(Get-ChildItem -LiteralPath $assets -File | ForEach-Object FullName)
    & $GitHubPath release upload $tag @assetFiles --repo merlinJeyakumar/future-notes
    if ($LASTEXITCODE -ne 0) { throw 'Draft upload failed; release remains a draft for inspection.' }
    $published = & $GitHubPath release view $tag --repo merlinJeyakumar/future-notes --json assets | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $published.assets.Count -ne $assetFiles.Count) { throw 'Draft asset inventory mismatch.' }
    foreach ($file in $assetFiles) {
        $name = [IO.Path]::GetFileName($file)
        $remote = @($published.assets | Where-Object { $_.name -ceq $name })
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($remote.Count -ne 1 -or $remote[0].size -ne (Get-Item -LiteralPath $file).Length -or $remote[0].digest -ne "sha256:$hash") { throw "Draft asset verification failed: $name" }
    }
    $oldTagAfter = @(git ls-remote --tags origin 'refs/tags/v1.0.0*')
    if ($LASTEXITCODE -ne 0 -or ($oldTag -join "`n") -cne ($oldTagAfter -join "`n") -or
        (git rev-parse refs/tags/v1.0.0).Trim() -cne $oldLocalTag) { throw 'Existing tag changed; stop publication.' }
    & $GitHubPath release edit $tag --repo merlinJeyakumar/future-notes --draft=false --latest
    if ($LASTEXITCODE -ne 0) { throw 'Verified draft could not be published.' }
    & $GitHubPath release view $tag --repo merlinJeyakumar/future-notes --json url,isDraft,tagName
    if ($LASTEXITCODE -ne 0) { throw 'Final release verification failed.' }
} finally { Pop-Location }
