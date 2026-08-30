[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$DistRoot,
    [switch]$SelfCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Windows package smoke failed: $Message"
    }
}

function Get-JsonPropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }
    return $property.Value
}

function Get-ExecutableFromCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    if ($Command -match '^\s*"([^"]+[.]exe)"') {
        return $Matches[1]
    }
    if ($Command -match '^\s*(.+?[.]exe)(?:,-?\d+)?(?:\s|$)') {
        return $Matches[1].Trim()
    }
    return ""
}

function Get-UninstallEntries {
    param([Parameter(Mandatory = $true)][string]$ProductName)

    $registryPatterns = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $entries = foreach ($pattern in $registryPatterns) {
        Get-ItemProperty -Path $pattern -ErrorAction SilentlyContinue | Where-Object {
            $displayNameProperty = $_.PSObject.Properties["DisplayName"]
            if ($null -eq $displayNameProperty) {
                return $false
            }
            $displayName = [string]$displayNameProperty.Value
            $displayName -eq $ProductName -or $displayName.StartsWith("$ProductName ", [StringComparison]::Ordinal)
        }
    }
    return @($entries)
}

function Get-ProcessIds {
    param([Parameter(Mandatory = $true)][string]$ExecutableName)

    return @(Get-Process -Name $ExecutableName -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Wait-ForNewVisibleProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [int[]]$PreviousIds = @(),
        [int]$TimeoutSeconds = 25
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $candidates = @(Get-Process -Name $ExecutableName -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -notin $PreviousIds -and -not $_.HasExited
        })
        foreach ($candidate in $candidates) {
            try {
                $candidate.Refresh()
                if ($candidate.MainWindowHandle -ne 0) {
                    return $candidate
                }
            }
            catch {
                # A short-lived Chromium helper may exit while being inspected.
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    return $null
}

function Stop-NewAppProcesses {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [int[]]$PreviousIds = @()
    )

    $processes = @(Get-Process -Name $ExecutableName -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -notin $PreviousIds -and -not $_.HasExited
    })
    foreach ($process in $processes) {
        try {
            if ($process.MainWindowHandle -ne 0) {
                $null = $process.CloseMainWindow()
            }
        }
        catch {
            # Continue to the bounded forced cleanup below.
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        $remaining = @(Get-Process -Name $ExecutableName -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -notin $PreviousIds -and -not $_.HasExited
        })
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    Get-Process -Name $ExecutableName -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -notin $PreviousIds -and -not $_.HasExited
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-SilentExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @("/S"),
        [int]$TimeoutSeconds = 120
    )

    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "timed out while running $Path"
    }
    Assert-Condition ($process.ExitCode -eq 0) "$Path exited with $($process.ExitCode)"
}

function Resolve-InstalledExecutable {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ExecutableName
    )

    $installLocation = [string](Get-JsonPropertyValue -Object $Entry -Name "InstallLocation" -DefaultValue "")
    if (-not [string]::IsNullOrWhiteSpace($installLocation)) {
        $candidate = Join-Path $installLocation "$ExecutableName.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $displayIcon = [string](Get-JsonPropertyValue -Object $Entry -Name "DisplayIcon" -DefaultValue "")
    if (-not [string]::IsNullOrWhiteSpace($displayIcon)) {
        $candidate = Get-ExecutableFromCommand $displayIcon
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return ""
}

function Invoke-SelfCheck {
    Assert-Condition ((Get-ExecutableFromCommand '"C:\Program Files\WeiBei\Uninstall WeiBei.exe" /S') -eq "C:\Program Files\WeiBei\Uninstall WeiBei.exe") "quoted uninstall parser"
    Assert-Condition ((Get-ExecutableFromCommand "C:\Tools\uninstall.exe /quiet") -eq "C:\Tools\uninstall.exe") "plain uninstall parser"
    Assert-Condition ((Get-ExecutableFromCommand "C:\Program Files\WeiBei\WeiBei.exe,0") -eq "C:\Program Files\WeiBei\WeiBei.exe") "unquoted display icon parser"
    Assert-Condition ((Get-ExecutableFromCommand "C:\Program Files\WeiBei\WeiBei.exe,-1") -eq "C:\Program Files\WeiBei\WeiBei.exe") "negative display icon parser"
    Assert-Condition ([string]::IsNullOrWhiteSpace((Get-ExecutableFromCommand "not-an-executable"))) "invalid uninstall parser"
    Write-Host "Windows package smoke self-check passed"
}

if ($SelfCheck) {
    Invoke-SelfCheck
    exit 0
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
}
if ([string]::IsNullOrWhiteSpace($DistRoot)) {
    $DistRoot = Join-Path $RepositoryRoot "windows/release"
}

$version = (Get-Content -LiteralPath (Join-Path $RepositoryRoot "VERSION") -Raw).Trim()
$windowsPackage = Get-Content -LiteralPath (Join-Path $RepositoryRoot "windows/package.json") -Raw | ConvertFrom-Json
$build = Get-JsonPropertyValue -Object $windowsPackage -Name "build"
$productName = [string](Get-JsonPropertyValue -Object $build -Name "productName" -DefaultValue $windowsPackage.name)
$executableName = [string](Get-JsonPropertyValue -Object $build -Name "executableName" -DefaultValue $productName)

$setupArtifacts = @(Get-ChildItem -LiteralPath $DistRoot -File | Where-Object { $_.Name -match "(?i)-Setup[.]exe$" })
$portableArtifacts = @(Get-ChildItem -LiteralPath $DistRoot -File | Where-Object { $_.Name -match "(?i)-Portable[.]exe$" })
Assert-Condition ($setupArtifacts.Count -eq 1) "expected exactly one NSIS Setup executable"
Assert-Condition ($portableArtifacts.Count -eq 1) "expected exactly one Portable executable"
$setup = $setupArtifacts[0]
$portable = $portableArtifacts[0]

$entriesBeforeInstall = @(Get-UninstallEntries -ProductName $productName)
Assert-Condition ($entriesBeforeInstall.Count -eq 0) "runner already has a $productName installation"
$processIdsBeforeInstall = @(Get-ProcessIds -ExecutableName $executableName)

try {
    Invoke-SilentExecutable -Path $setup.FullName
    Stop-NewAppProcesses -ExecutableName $executableName -PreviousIds $processIdsBeforeInstall

    $installedEntries = @(Get-UninstallEntries -ProductName $productName)
    Assert-Condition ($installedEntries.Count -eq 1) "NSIS did not create exactly one uninstall entry"
    $entry = $installedEntries[0]
    Assert-Condition ([string]$entry.PSPath -match "HKEY_CURRENT_USER") "NSIS candidate was not installed per-user"
    $displayVersion = [string](Get-JsonPropertyValue -Object $entry -Name "DisplayVersion" -DefaultValue "")
    Assert-Condition ([string]::IsNullOrWhiteSpace($displayVersion) -or $displayVersion.StartsWith($version, [StringComparison]::Ordinal)) "uninstall entry version does not match $version"

    $installedExecutable = Resolve-InstalledExecutable -Entry $entry -ExecutableName $executableName
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($installedExecutable)) "could not resolve installed app executable"
    $normalizedInstallPath = [System.IO.Path]::GetFullPath($installedExecutable)
    $normalizedLocalAppData = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    Assert-Condition ($normalizedInstallPath.StartsWith($normalizedLocalAppData, [StringComparison]::OrdinalIgnoreCase)) "per-user install escaped LOCALAPPDATA"

    $knownIds = @(Get-ProcessIds -ExecutableName $executableName)
    $launched = Start-Process -FilePath $installedExecutable -PassThru
    $visible = Wait-ForNewVisibleProcess -ExecutableName $executableName -PreviousIds $knownIds
    Assert-Condition ($null -ne $visible) "installed app did not produce a visible window"
    Assert-Condition (-not $launched.HasExited) "installed app launcher exited before smoke completed"
    Stop-NewAppProcesses -ExecutableName $executableName -PreviousIds $knownIds

    $expectedUserData = Join-Path $env:APPDATA $productName
    [System.IO.Directory]::CreateDirectory($expectedUserData) | Out-Null
    $sentinel = Join-Path $expectedUserData "ci-uninstall-preserves-user-data.txt"
    Set-Content -LiteralPath $sentinel -Value "weibei-$version" -Encoding utf8

    # A same-version reinstall exercises the NSIS upgrade/repair path and must
    # neither duplicate registry entries nor discard user data.
    Invoke-SilentExecutable -Path $setup.FullName
    Stop-NewAppProcesses -ExecutableName $executableName -PreviousIds $processIdsBeforeInstall
    $entriesAfterReinstall = @(Get-UninstallEntries -ProductName $productName)
    Assert-Condition ($entriesAfterReinstall.Count -eq 1) "same-version reinstall duplicated uninstall entries"
    Assert-Condition (Test-Path -LiteralPath $sentinel -PathType Leaf) "same-version reinstall discarded user data"
    Assert-Condition (Test-Path -LiteralPath $installedExecutable -PathType Leaf) "same-version reinstall removed the app"

    $entry = $entriesAfterReinstall[0]
    $quietCommand = [string](Get-JsonPropertyValue -Object $entry -Name "QuietUninstallString" -DefaultValue "")
    $uninstallCommand = if ([string]::IsNullOrWhiteSpace($quietCommand)) {
        [string](Get-JsonPropertyValue -Object $entry -Name "UninstallString" -DefaultValue "")
    }
    else {
        $quietCommand
    }
    $uninstaller = Get-ExecutableFromCommand $uninstallCommand
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($uninstaller)) "could not parse uninstaller path"
    Assert-Condition (Test-Path -LiteralPath $uninstaller -PathType Leaf) "uninstaller does not exist: $uninstaller"
    Invoke-SilentExecutable -Path $uninstaller

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $remainingEntries = @(Get-UninstallEntries -ProductName $productName)
        if ($remainingEntries.Count -eq 0 -and -not (Test-Path -LiteralPath $installedExecutable)) {
            break
        }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    Assert-Condition ((Get-UninstallEntries -ProductName $productName).Count -eq 0) "uninstall entry remained after uninstall"
    Assert-Condition (-not (Test-Path -LiteralPath $installedExecutable)) "installed executable remained after uninstall"
    Assert-Condition (Test-Path -LiteralPath $sentinel -PathType Leaf) "uninstall deleted user data"

    $entriesBeforePortable = @(Get-UninstallEntries -ProductName $productName)
    $portableKnownIds = @(Get-ProcessIds -ExecutableName $executableName)
    $portableLauncher = Start-Process -FilePath $portable.FullName -PassThru
    $portableVisible = Wait-ForNewVisibleProcess -ExecutableName $executableName -PreviousIds $portableKnownIds -TimeoutSeconds 35
    Assert-Condition ($null -ne $portableVisible) "Portable candidate did not produce a visible app window"
    if ($portableLauncher.HasExited) {
        Assert-Condition ($portableLauncher.ExitCode -eq 0) "Portable launcher exited with $($portableLauncher.ExitCode)"
    }
    Stop-NewAppProcesses -ExecutableName $executableName -PreviousIds $portableKnownIds
    $entriesAfterPortable = @(Get-UninstallEntries -ProductName $productName)
    Assert-Condition ($entriesAfterPortable.Count -eq $entriesBeforePortable.Count) "Portable candidate created an uninstall registry entry"

    Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
}
finally {
    Stop-NewAppProcesses -ExecutableName $executableName -PreviousIds $processIdsBeforeInstall
    $leftovers = @(Get-UninstallEntries -ProductName $productName)
    foreach ($leftover in $leftovers) {
        $command = [string](Get-JsonPropertyValue -Object $leftover -Name "QuietUninstallString" -DefaultValue "")
        if ([string]::IsNullOrWhiteSpace($command)) {
            $command = [string](Get-JsonPropertyValue -Object $leftover -Name "UninstallString" -DefaultValue "")
        }
        $path = Get-ExecutableFromCommand $command
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            try { Invoke-SilentExecutable -Path $path } catch { Write-Warning $_ }
        }
    }
}

Write-Host "windows_smoke_setup=$($setup.FullName)"
Write-Host "windows_smoke_portable=$($portable.FullName)"
Write-Host "Windows NSIS and Portable smoke passed"
