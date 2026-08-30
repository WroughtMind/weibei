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
        throw "Windows package verification failed: $Message"
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

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($stream.Length -lt 132) {
            throw "file is too short to be a PE image: $Path"
        }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or ($peOffset + 6) -gt $stream.Length) {
            throw "invalid PE header offset in $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "missing PE signature in $Path"
        }
        switch ($reader.ReadUInt16()) {
            0x8664 { return "x64" }
            0xaa64 { return "arm64" }
            0x014c { return "x86" }
            default { return "unknown" }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Test-IsForbiddenPackagedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Replace("\", "/").TrimStart("/")
    if ($normalized -match "(?i)(^|/)[.]env([.]|$)") {
        return $true
    }
    if ($normalized -match "(?i)(^|/)(playwright-report|test-results|e2e|fixtures)(/|$)") {
        return $true
    }
    if ($normalized -match "(?i)(^|/)playwright[.]config[.]") {
        return $true
    }
    if ($normalized -match "(?i)^dist/(main|renderer)/.*[.]map$") {
        return $true
    }
    if ($normalized -match "(?i)^src/") {
        return $true
    }
    return $false
}

function New-TestPeFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][UInt16]$Machine
    )

    $bytes = [byte[]]::new(256)
    [BitConverter]::GetBytes([int]128).CopyTo($bytes, 0x3c)
    [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes, 128)
    [BitConverter]::GetBytes($Machine).CopyTo($bytes, 132)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Invoke-NativeSqliteFtsProbe {
    param(
        [Parameter(Mandatory = $true)][string]$ElectronExecutable,
        [Parameter(Mandatory = $true)][string]$ModuleRoot
    )

    $probePath = Join-Path ([System.IO.Path]::GetTempPath()) "weibei-sqlite-probe-$([Guid]::NewGuid()).cjs"
    $probe = @'
const Database = require(process.argv[2]);
const database = new Database(":memory:");
try {
  database.exec("CREATE VIRTUAL TABLE documents USING fts5(body); INSERT INTO documents(body) VALUES ('weibei citation workspace');");
  const row = database.prepare("SELECT count(*) AS count FROM documents WHERE documents MATCH ?").get("citation");
  if (!row || row.count !== 1) process.exit(3);
} finally {
  database.close();
}
'@
    Set-Content -LiteralPath $probePath -Value $probe -Encoding utf8
    $previousRunAsNode = $env:ELECTRON_RUN_AS_NODE
    try {
        $env:ELECTRON_RUN_AS_NODE = "1"
        $process = Start-Process -FilePath $ElectronExecutable -ArgumentList @(
            "`"$probePath`"",
            "`"$ModuleRoot`""
        ) -Wait -PassThru
        Assert-Condition ($process.ExitCode -eq 0) "packaged better-sqlite3 could not load in Electron or FTS5 was unavailable"
    }
    finally {
        if ($null -eq $previousRunAsNode) {
            Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
        }
        else {
            $env:ELECTRON_RUN_AS_NODE = $previousRunAsNode
        }
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PackagedSidecarChecks {
    param([Parameter(Mandatory = $true)][string]$ResourcesRoot)

    $helpersRoot = Join-Path $ResourcesRoot "helpers"
    if (-not (Test-Path -LiteralPath $helpersRoot -PathType Container)) {
        return
    }

    $helpers = @(Get-ChildItem -LiteralPath $helpersRoot -Recurse -File -Filter "*.exe")
    Assert-Condition ($helpers.Count -gt 0) "packaged helpers directory contains no executable sidecar"
    foreach ($helper in $helpers) {
        Assert-Condition ((Get-PeMachine -Path $helper.FullName) -eq "x64") "sidecar is not Windows x64: $($helper.Name)"
        $process = Start-Process -FilePath $helper.FullName -ArgumentList @("--self-check") -PassThru
        if (-not $process.WaitForExit(60000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "sidecar self-check timed out: $($helper.Name)"
        }
        Assert-Condition ($process.ExitCode -eq 0) "sidecar self-check failed: $($helper.Name)"
    }
}

function Invoke-SelfCheck {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "weibei-package-verify-$([Guid]::NewGuid())"
    [System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
    try {
        $x64 = Join-Path $temporaryRoot "x64.exe"
        $arm64 = Join-Path $temporaryRoot "arm64.exe"
        New-TestPeFile -Path $x64 -Machine 0x8664
        New-TestPeFile -Path $arm64 -Machine 0xaa64
        Assert-Condition ((Get-PeMachine -Path $x64) -eq "x64") "x64 PE parser self-check"
        Assert-Condition ((Get-PeMachine -Path $arm64) -eq "arm64") "arm64 PE parser self-check"
        Assert-Condition (Test-IsForbiddenPackagedPath "dist/renderer/index.js.map") "source-map hygiene self-check"
        Assert-Condition (Test-IsForbiddenPackagedPath "fixtures/private.md") "fixture hygiene self-check"
        Assert-Condition (-not (Test-IsForbiddenPackagedPath "node_modules/library/index.js")) "dependency path hygiene self-check"
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Windows package verifier self-check passed"
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

$versionPath = Join-Path $RepositoryRoot "VERSION"
$rootPackagePath = Join-Path $RepositoryRoot "package.json"
$windowsPackagePath = Join-Path $RepositoryRoot "windows/package.json"
Assert-Condition (Test-Path -LiteralPath $versionPath -PathType Leaf) "missing VERSION"
Assert-Condition (Test-Path -LiteralPath $rootPackagePath -PathType Leaf) "missing root package.json"
Assert-Condition (Test-Path -LiteralPath $windowsPackagePath -PathType Leaf) "missing windows/package.json"
Assert-Condition (Test-Path -LiteralPath $DistRoot -PathType Container) "missing Windows release directory: $DistRoot"

$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
$rootPackage = Get-Content -LiteralPath $rootPackagePath -Raw | ConvertFrom-Json
$windowsPackage = Get-Content -LiteralPath $windowsPackagePath -Raw | ConvertFrom-Json
Assert-Condition ($version -match "^[0-9]+[.][0-9]+[.][0-9]+$") "VERSION must be numeric major.minor.patch"
Assert-Condition ([string]$rootPackage.version -eq $version) "root package.json version does not match VERSION"
Assert-Condition ([string]$windowsPackage.version -eq $version) "windows/package.json version does not match VERSION"

$build = Get-JsonPropertyValue -Object $windowsPackage -Name "build"
Assert-Condition ($null -ne $build) "windows/package.json has no electron-builder configuration"
$appId = [string](Get-JsonPropertyValue -Object $build -Name "appId" -DefaultValue "")
$productName = [string](Get-JsonPropertyValue -Object $build -Name "productName" -DefaultValue $windowsPackage.name)
$executableName = [string](Get-JsonPropertyValue -Object $build -Name "executableName" -DefaultValue $productName)
Assert-Condition (-not [string]::IsNullOrWhiteSpace($appId)) "electron-builder appId must be explicit and stable"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($productName)) "electron-builder productName is empty"
Assert-Condition (-not [string]::IsNullOrWhiteSpace($executableName)) "electron-builder executableName is empty"

$setupArtifacts = @(Get-ChildItem -LiteralPath $DistRoot -File | Where-Object { $_.Name -match "(?i)-Setup[.]exe$" })
$portableArtifacts = @(Get-ChildItem -LiteralPath $DistRoot -File | Where-Object { $_.Name -match "(?i)-Portable[.]exe$" })
Assert-Condition ($setupArtifacts.Count -eq 1) "expected exactly one *-Setup.exe, found $($setupArtifacts.Count)"
Assert-Condition ($portableArtifacts.Count -eq 1) "expected exactly one *-Portable.exe, found $($portableArtifacts.Count)"
$setup = $setupArtifacts[0]
$portable = $portableArtifacts[0]
Assert-Condition ($setup.FullName -ne $portable.FullName) "NSIS and Portable artifacts resolved to the same file"
Assert-Condition ($setup.Name.Contains($version)) "NSIS artifact name does not contain version $version"
Assert-Condition ($portable.Name.Contains($version)) "Portable artifact name does not contain version $version"
Assert-Condition ($setup.Name -match "(?i)(x64|x86_64)") "NSIS artifact name does not declare x64"
Assert-Condition ($portable.Name -match "(?i)(x64|x86_64)") "Portable artifact name does not declare x64"
Assert-Condition ($setup.Length -gt 1MB) "NSIS artifact is unexpectedly small"
Assert-Condition ($portable.Length -gt 1MB) "Portable artifact is unexpectedly small"

$unpackedRoot = Join-Path $DistRoot "win-unpacked"
$appExecutable = Join-Path $unpackedRoot "$executableName.exe"
$resourcesRoot = Join-Path $unpackedRoot "resources"
$asarPath = Join-Path $resourcesRoot "app.asar"
Assert-Condition (Test-Path -LiteralPath $unpackedRoot -PathType Container) "missing win-unpacked candidate"
Assert-Condition (Test-Path -LiteralPath $appExecutable -PathType Leaf) "missing unpacked app executable: $appExecutable"
Assert-Condition ((Get-PeMachine -Path $appExecutable) -eq "x64") "unpacked app executable is not x64"
Assert-Condition (Test-Path -LiteralPath $asarPath -PathType Leaf) "missing resources/app.asar"

$productVersion = [string](Get-Item -LiteralPath $appExecutable).VersionInfo.ProductVersion
Assert-Condition (-not [string]::IsNullOrWhiteSpace($productVersion)) "app executable has no ProductVersion"
Assert-Condition ($productVersion.StartsWith($version, [StringComparison]::Ordinal)) "app ProductVersion $productVersion does not match $version"

$nativeSqlitePath = Join-Path $resourcesRoot "app.asar.unpacked/node_modules/better-sqlite3/prebuilds/win32-x64.node"
Assert-Condition (Test-Path -LiteralPath $nativeSqlitePath -PathType Leaf) "missing unpacked better-sqlite3 Windows x64 prebuild"
$nativeSqlite = Get-Item -LiteralPath $nativeSqlitePath
Assert-Condition ((Get-PeMachine -Path $nativeSqlite.FullName) -eq "x64") "better-sqlite3 Windows prebuild is not x64"
$betterSqliteRoot = $nativeSqlite.Directory.Parent.FullName
Assert-Condition (Test-Path -LiteralPath (Join-Path $betterSqliteRoot "package.json") -PathType Leaf) "could not resolve packaged better-sqlite3 module root"
Invoke-NativeSqliteFtsProbe -ElectronExecutable $appExecutable -ModuleRoot $betterSqliteRoot
Invoke-PackagedSidecarChecks -ResourcesRoot $resourcesRoot

$asarCandidates = @(
    (Join-Path $RepositoryRoot "node_modules/.bin/asar.cmd"),
    (Join-Path $RepositoryRoot "windows/node_modules/.bin/asar.cmd"),
    (Join-Path $RepositoryRoot "node_modules/.bin/asar"),
    (Join-Path $RepositoryRoot "windows/node_modules/.bin/asar")
)
$availableAsarCommands = @($asarCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
Assert-Condition ($availableAsarCommands.Count -gt 0) "locked @electron/asar command is unavailable"
$asarOutput = @(& $availableAsarCommands[0] list $asarPath 2>&1)
Assert-Condition ($LASTEXITCODE -eq 0) "could not inspect app.asar with the locked @electron/asar tool"
$forbiddenEntries = @($asarOutput | Where-Object { Test-IsForbiddenPackagedPath ([string]$_) })
Assert-Condition ($forbiddenEntries.Count -eq 0) "app.asar contains source maps, test fixtures, Playwright output, source files, or environment files"

$looseFiles = @(Get-ChildItem -LiteralPath $resourcesRoot -Recurse -File -ErrorAction SilentlyContinue)
$forbiddenLooseFiles = @($looseFiles | Where-Object {
    $relative = [System.IO.Path]::GetRelativePath($resourcesRoot, $_.FullName)
    Test-IsForbiddenPackagedPath $relative
})
Assert-Condition ($forbiddenLooseFiles.Count -eq 0) "loose packaged resources contain source maps, test fixtures, Playwright output, source files, or environment files"

$legalFiles = @("PRIVACY.md", "THIRD_PARTY_NOTICES.md", "ASSET_ATTRIBUTIONS.md")
foreach ($legalFile in $legalFiles) {
    $matches = @(Get-ChildItem -LiteralPath $resourcesRoot -Recurse -File -Filter $legalFile -ErrorAction SilentlyContinue)
    Assert-Condition ($matches.Count -eq 1) "packaged resources must contain exactly one $legalFile"
}

$extraResources = Get-JsonPropertyValue -Object $build -Name "extraResources" -DefaultValue @()
foreach ($entry in @($extraResources)) {
    if ($entry -is [string]) {
        $target = [System.IO.Path]::GetFileName([string]$entry)
    }
    else {
        $target = [string](Get-JsonPropertyValue -Object $entry -Name "to" -DefaultValue "")
        if ([string]::IsNullOrWhiteSpace($target)) {
            $source = [string](Get-JsonPropertyValue -Object $entry -Name "from" -DefaultValue "")
            $target = [System.IO.Path]::GetFileName($source.TrimEnd([char[]]@('/', '\')))
        }
    }
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($target)) "extraResources entry has no resolvable target"
    Assert-Condition (Test-Path -LiteralPath (Join-Path $resourcesRoot $target)) "extraResources target was not packaged: $target"
}

$requireSignature = $env:WEIBEI_REQUIRE_WINDOWS_SIGNATURE -eq "1"
if (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue) {
    foreach ($artifact in @($setup, $portable, (Get-Item -LiteralPath $appExecutable))) {
        $status = (Get-AuthenticodeSignature -LiteralPath $artifact.FullName).Status
        if ($requireSignature) {
            Assert-Condition ($status -eq [System.Management.Automation.SignatureStatus]::Valid) "$($artifact.Name) does not have a valid Authenticode signature"
        }
        else {
            Assert-Condition ($status -in @(
                [System.Management.Automation.SignatureStatus]::Valid,
                [System.Management.Automation.SignatureStatus]::NotSigned
            )) "$($artifact.Name) has an invalid Authenticode status: $status"
        }
    }
}

$hashTargets = @($setup, $portable, (Get-Item -LiteralPath $appExecutable), $nativeSqlite)
$extraResourceFiles = @()
foreach ($entry in @($extraResources)) {
    if ($entry -is [string]) {
        $target = [System.IO.Path]::GetFileName([string]$entry)
    }
    else {
        $target = [string](Get-JsonPropertyValue -Object $entry -Name "to" -DefaultValue "")
        if ([string]::IsNullOrWhiteSpace($target)) {
            $source = [string](Get-JsonPropertyValue -Object $entry -Name "from" -DefaultValue "")
            $target = [System.IO.Path]::GetFileName($source.TrimEnd([char[]]@('/', '\')))
        }
    }
    $packagedTarget = Join-Path $resourcesRoot $target
    if (Test-Path -LiteralPath $packagedTarget -PathType Leaf) {
        $extraResourceFiles += Get-Item -LiteralPath $packagedTarget
    }
    elseif (Test-Path -LiteralPath $packagedTarget -PathType Container) {
        $extraResourceFiles += Get-ChildItem -LiteralPath $packagedTarget -Recurse -File
    }
}
$hashTargets += $extraResourceFiles
$hashLines = @($hashTargets | Sort-Object -Property FullName -Unique | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $relative = [System.IO.Path]::GetRelativePath($DistRoot, $_.FullName).Replace("\", "/")
    "$hash  $relative"
})
$hashPath = Join-Path $DistRoot "WeiBei-$version-Windows-x64.sha256"
Set-Content -LiteralPath $hashPath -Value $hashLines -Encoding utf8

Write-Host "windows_package_version=$version"
Write-Host "windows_package_setup=$($setup.FullName)"
Write-Host "windows_package_portable=$($portable.FullName)"
Write-Host "windows_package_app=$appExecutable"
Write-Host "windows_package_native_sqlite=$($nativeSqlite.FullName)"
Write-Host "windows_package_hashes=$hashPath"
Write-Host "Windows package verification passed"
