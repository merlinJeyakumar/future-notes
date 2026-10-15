[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Verify')][string]$Mode = 'Prepare',
    [ValidatePattern('^[A-Za-z0-9-]+$')][string]$SnapshotId = '20261013'
)

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$configurationPath = Join-Path $workspace '.validation/future-notes-activation-config-20261013/locations.json'
$backupRoot = Join-Path $workspace ".validation/future-notes-backup-activation-$SnapshotId"
$rehearsalRoot = Join-Path $workspace ".validation/future-notes-validation-activation-rehearsal-$SnapshotId"
$phase = 'admission'

function Assert-NoApp {
    if (@(Get-Process -Name FutureNotes,flutter_application_1 -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'A project app is running.'
    }
}

function Assert-NoLinks([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Linked storage is not admitted.'
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
}

function Get-Inventory([string]$Root) {
    Assert-NoLinks $Root
    $prefix = $Root.TrimEnd('\') + '\'
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($Root)
    $found = [Collections.Generic.List[object]]::new()
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        Assert-NoLinks $directory
        foreach ($child in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A linked entry was found.'
            }
            $found.Add($child)
            if ($child.PSIsContainer) { $pending.Enqueue($child.FullName) }
        }
    }
    $items = @($found | Sort-Object FullName)
    $result = foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A linked entry was found.'
        }
        if (-not $item.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Inventory containment failed.'
        }
        $hash = $null
        $length = $null
        if (-not $item.PSIsContainer) {
            $length = $item.Length
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
            $after = Get-Item -LiteralPath $item.FullName -Force
            if ($length -ne $after.Length -or $item.LastWriteTimeUtc -ne $after.LastWriteTimeUtc) {
                throw 'A source changed while hashing.'
            }
        }
        [pscustomobject]@{
            relative = $item.FullName.Substring($prefix.Length)
            directory = $item.PSIsContainer
            length = $length
            sha256 = $hash
            modifiedUtc = $item.LastWriteTimeUtc.ToString('o')
        }
    }
    return @($result)
}

function Assert-Matches($Expected, $Actual) {
    # Relative names remain in the private manifest; never emit them to logs.
    if (($Expected | ConvertTo-Json -Depth 8 -Compress) -cne ($Actual | ConvertTo-Json -Depth 8 -Compress)) {
        throw 'Inventory verification failed.'
    }
}

function Copy-AccessRules([string]$Source, [string]$Destination) {
    $access = Get-Acl -LiteralPath $Source
    # Retain the original effective DACL, rather than inheriting broader access
    # from the workspace containing these private copies.
    $access.SetAccessRuleProtection($true, $true)
    Set-Acl -LiteralPath $Destination -AclObject $access
}

function Copy-VerifiedTree([string]$Source, [string]$Destination, $Inventory) {
    if (Test-Path -LiteralPath $Destination) { throw 'Copy destination already exists.' }
    $null = New-Item -ItemType Directory -Path $Destination
    Copy-AccessRules $Source $Destination
    # Create parents first. Never use recursive copy, which could follow a link.
    foreach ($entry in @($Inventory | Where-Object directory | Sort-Object { $_.relative.Length })) {
        $target = Join-Path $Destination $entry.relative
        $null = New-Item -ItemType Directory -Path $target
        Copy-AccessRules (Join-Path $Source $entry.relative) $target
    }
    foreach ($entry in @($Inventory | Where-Object { -not $_.directory })) {
        $sourceHandlePath = Join-Path $Source $entry.relative
        $destinationHandlePath = Join-Path $Destination $entry.relative
        Assert-NoLinks $sourceHandlePath
        $sourceHandle = $null
        $destinationHandle = $null
        try {
            $sourceHandle = [IO.File]::Open($sourceHandlePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $destinationHandle = [IO.File]::Open($destinationHandlePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $sourceHandle.CopyTo($destinationHandle, 1048576)
            $destinationHandle.Flush($true)
        } finally {
            if ($null -ne $destinationHandle) { $destinationHandle.Dispose() }
            if ($null -ne $sourceHandle) { $sourceHandle.Dispose() }
        }
        Copy-AccessRules $sourceHandlePath $destinationHandlePath
        [IO.File]::SetLastWriteTimeUtc($destinationHandlePath, [DateTime]::Parse($entry.modifiedUtc).ToUniversalTime())
    }
    # Child creation changes directory timestamps; restore them last.
    foreach ($entry in @($Inventory | Where-Object directory | Sort-Object { $_.relative.Length } -Descending)) {
        [IO.Directory]::SetLastWriteTimeUtc((Join-Path $Destination $entry.relative), [DateTime]::Parse($entry.modifiedUtc).ToUniversalTime())
    }
    Assert-Matches $Inventory (Get-Inventory $Destination)
}

try {
    Assert-NoApp
    $locations = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
    if ($locations.verifiedDiscovery -ne $true) { throw 'Native discovery is not verified.' }
    $sourceRoot = [IO.Path]::GetFullPath($locations.notesRoot)
    $settingsPath = [IO.Path]::GetFullPath($locations.settingsFile)
    # This reviewed rollout admits only the observed shared UserData layout.
    if ([IO.Path]::GetDirectoryName($settingsPath) -ine $sourceRoot -or [IO.Path]::GetFileName($settingsPath) -cne 'settings.json') {
        throw 'The reviewed storage layout changed.'
    }
    $validationPrefix = [IO.Path]::GetFullPath((Join-Path $workspace '.validation')).TrimEnd('\') + '\'
    foreach ($destination in @($backupRoot, $rehearsalRoot)) {
        if (-not $destination.StartsWith($validationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $sourceRoot.StartsWith($destination, [StringComparison]::OrdinalIgnoreCase) -or
            $destination.StartsWith($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Backup/rehearsal containment failed.'
        }
        Assert-NoLinks $destination
    }
    Assert-NoLinks $sourceRoot
    $manifestPath = Join-Path $backupRoot 'manifest.json'
    if ($Mode -eq 'Verify') {
        $phase = 'retained backup manifest read'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -DateKind String
        if ($manifest.complete -ne $true) { throw 'Backup was not acknowledged.' }
        $phase = 'recovery rehearsal receipt verification'
        $rehearsed = Get-Content -LiteralPath (Join-Path $rehearsalRoot 'rehearsal-result.json') -Raw | ConvertFrom-Json
        if ($rehearsed.version -ne 1 -or $rehearsed.complete -ne $true) {
            throw 'Recovery rehearsal has not completed.'
        }
        $phase = 'current original inventory verification'
        Assert-Matches $manifest.inventory (Get-Inventory $sourceRoot)
        $phase = 'retained backup inventory verification'
        Assert-Matches $manifest.inventory (Get-Inventory (Join-Path $backupRoot 'library'))
        $phase = 'single-instance verification'
        Assert-NoApp
        Write-Output 'Original library and retained backup still match the verified inventory.'
        exit 0
    }
    foreach ($destination in @($backupRoot, $rehearsalRoot)) {
        if (Test-Path -LiteralPath $destination) { throw 'Unexpected retained destination; refusing overwrite.' }
    }
    $phase = 'backup inventory'
    $before = Get-Inventory $sourceRoot
    $null = New-Item -ItemType Directory -Path $backupRoot
    Copy-AccessRules $sourceRoot $backupRoot
    $phase = 'retained backup copy'
    Copy-VerifiedTree $sourceRoot (Join-Path $backupRoot 'library') $before
    $phase = 'source stability verification'
    Assert-Matches $before (Get-Inventory $sourceRoot)
    Assert-NoApp
    $phase = 'disposable rehearsal copy'
    $null = New-Item -ItemType Directory -Path $rehearsalRoot
    Copy-AccessRules $sourceRoot $rehearsalRoot
    Copy-VerifiedTree (Join-Path $backupRoot 'library') (Join-Path $rehearsalRoot 'library') $before
    $phase = 'previous executable preservation'
    $oldBinaryRoot = Join-Path $workspace 'build/windows/x64/runner/Debug'
    if (-not (Test-Path -LiteralPath (Join-Path $oldBinaryRoot 'flutter_application_1.exe'))) {
        throw 'Previous executable was not found.'
    }
    $binaryInventory = Get-Inventory $oldBinaryRoot
    Copy-VerifiedTree $oldBinaryRoot (Join-Path $backupRoot 'previous-executable') $binaryInventory
    $phase = 'backup acknowledgement'
    [pscustomobject]@{
        version = 1
        complete = $true
        settingsPresent = (Test-Path -LiteralPath $settingsPath)
        inventory = @($before)
        executableInventory = @($binaryInventory)
        sourceCommit = (git -C $workspace rev-parse HEAD)
        completedUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    [pscustomobject]@{ version = 1; backupVerified = $true; inventory = @($before) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rehearsalRoot 'admission.json') -Encoding UTF8
    [pscustomobject]@{
        FN_RECOVERABLE_STORAGE = 'true'
        FN_DATA_ROOT = $sourceRoot
        FN_SETTINGS_PATH = $settingsPath
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path $configurationPath) 'defines.json') -Encoding UTF8
    Write-Output ('Verified backup and separate rehearsal copy: {0} files; previous executable retained.' -f @($before | Where-Object { -not $_.directory }).Count)
} catch {
    # A partial destination is retained for inspection. Never delete to retry.
    Write-Output ('FAILED: storage activation preparation stopped during {0}. No original file was written; partial copies were retained.' -f $phase)
    exit 1
}
