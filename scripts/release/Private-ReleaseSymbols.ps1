function New-PrivateReleaseSymbols {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Workspace,
          [Parameter(Mandatory=$true)][string]$Version,
          [Parameter(Mandatory=$true)][string]$Revision)
    if ($Version -notmatch '^\d+\.\d+\.\d+\+\d+$' -or $Revision -notmatch '^[a-f0-9]{40}$') {
        throw 'Exact version and revision required for private symbols.'
    }
    # A PowerShell 7 parent can pass its PSModulePath to Windows PowerShell 5.
    # Load the security cmdlets belonging to this host, not an inherited module.
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    $root = Join-Path ([IO.Path]::GetFullPath($Workspace)) '.private-release-symbols'
    $ancestor = $root
    while ($ancestor) {
        if ((Test-Path -LiteralPath $ancestor) -and
            ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked private-symbol path rejected.'
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (!(Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root | Out-Null }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    # Change only the DACL. Set-Acl can request audit/label privileges that an
    # ordinary build user does not hold; no SACL or ownership change is needed.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($root), $acl)
    } else {
        [IO.Directory]::SetAccessControl($root, $acl)
    }
    $folder = Join-Path $root "$Version-$Revision-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $folder | Out-Null
    return $folder
}

function Assert-PrivateReleaseSymbols {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Directory)
    $symbols = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object {
        $_.Extension -in @('.symbols', '.pdb') -and $_.Length -gt 0
    })
    if ($symbols.Count -eq 0) { throw 'Private crash symbols were not produced.' }
    $map = Get-Content -LiteralPath (Join-Path $Directory 'obfuscation-map.json') -Raw | ConvertFrom-Json
    if ($map -isnot [array] -or $map.Count -lt 2 -or $map.Count % 2 -ne 0) {
        throw 'Private obfuscation map is missing or malformed.'
    }
    $renamed = $false
    for ($index = 0; $index -lt $map.Count; $index += 2) {
        if ($map[$index] -isnot [string] -or $map[$index + 1] -isnot [string]) {
            throw 'Private obfuscation map has invalid name pairs.'
        }
        if ($map[$index] -cne $map[$index + 1]) { $renamed = $true }
    }
    if (!$renamed) { throw 'Obfuscation map contains no renamed symbols.' }
}
