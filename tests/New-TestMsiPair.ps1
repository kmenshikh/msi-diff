<#
.SYNOPSIS
    Builds a pair of test MSI packages with known differences.

.DESCRIPTION
    The packages are created directly through the Windows Installer COM API and exist
    only to exercise Compare-Msi.ps1 - they are not meant to be installed.

.EXAMPLE
    .\tests\New-TestMsiPair.ps1 -OutputDirectory .\tests\out
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $here 'out' }
. (Join-Path (Split-Path -Parent $here) 'src\MsiCom.ps1')

function Invoke-MsiSql {
    param($Database, [string] $Sql, $Record)
    $view = Invoke-MsiMethod $Database 'OpenView' @($Sql)
    try {
        if ($Record) { $null = Invoke-MsiMethod $view 'Execute' @($Record) }
        else { $null = Invoke-MsiMethod $view 'Execute' }
    } finally {
        $null = Invoke-MsiMethod $view 'Close'
        Remove-MsiComObject $view
    }
}

function Add-MsiRow {
    param($Installer, $Database, [string] $Table, [hashtable] $Values)

    $columns = @($Values.Keys)
    $placeholders = @($columns | ForEach-Object { '?' })
    $sql = 'INSERT INTO `' + $Table + '` (`' + ($columns -join '`,`') + '`) VALUES (' + ($placeholders -join ',') + ')'

    $record = Invoke-MsiMethod $Installer 'CreateRecord' @($columns.Count)
    for ($i = 0; $i -lt $columns.Count; $i++) {
        $value = $Values[$columns[$i]]
        if ($null -eq $value) { continue }
        if ($value -is [int]) {
            Set-MsiComProperty $record 'IntegerData' @(($i + 1), [int]$value)
        } elseif ($value -is [hashtable] -and $value.ContainsKey('StreamFile')) {
            $null = Invoke-MsiMethod $record 'SetStream' @(($i + 1), $value['StreamFile'])
        } else {
            Set-MsiComProperty $record 'StringData' @(($i + 1), [string]$value)
        }
    }

    Invoke-MsiSql -Database $Database -Sql $sql -Record $record
    Remove-MsiComObject $record
}

function New-TestMsi {
    param(
        [string] $Path,
        [string] $ProductName,
        [string] $ProductVersion,
        [string] $ProductCode,
        [string] $PackageCode,
        [string] $BinaryPayload,
        [switch] $SecondRevision
    )

    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }

    $binaryFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($binaryFile, $BinaryPayload)

    $installer = New-MsiInstaller
    $database = $null
    try {
        # msiOpenDatabaseModeCreate = 3
        $database = Invoke-MsiMethod $installer 'OpenDatabase' @($Path, 3)

        $schema = @(
            'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) NOT NULL PRIMARY KEY `Property`)',
            'CREATE TABLE `Directory` (`Directory` CHAR(72) NOT NULL, `Directory_Parent` CHAR(72), `DefaultDir` CHAR(255) NOT NULL PRIMARY KEY `Directory`)',
            'CREATE TABLE `Component` (`Component` CHAR(72) NOT NULL, `ComponentId` CHAR(38), `Directory_` CHAR(72) NOT NULL, `Attributes` INTEGER NOT NULL, `Condition` CHAR(255), `KeyPath` CHAR(72) PRIMARY KEY `Component`)',
            'CREATE TABLE `Feature` (`Feature` CHAR(38) NOT NULL, `Feature_Parent` CHAR(38), `Title` CHAR(64), `Description` CHAR(255), `Display` INTEGER, `Level` INTEGER NOT NULL, `Directory_` CHAR(72), `Attributes` INTEGER NOT NULL PRIMARY KEY `Feature`)',
            'CREATE TABLE `FeatureComponents` (`Feature_` CHAR(38) NOT NULL, `Component_` CHAR(72) NOT NULL PRIMARY KEY `Feature_`, `Component_`)',
            'CREATE TABLE `File` (`File` CHAR(72) NOT NULL, `Component_` CHAR(72) NOT NULL, `FileName` CHAR(255) NOT NULL, `FileSize` LONG NOT NULL, `Version` CHAR(72), `Language` CHAR(20), `Attributes` INTEGER, `Sequence` LONG NOT NULL PRIMARY KEY `File`)',
            'CREATE TABLE `MsiFileHash` (`File_` CHAR(72) NOT NULL, `Options` INTEGER NOT NULL, `HashPart1` LONG NOT NULL, `HashPart2` LONG NOT NULL, `HashPart3` LONG NOT NULL, `HashPart4` LONG NOT NULL PRIMARY KEY `File_`)',
            'CREATE TABLE `Registry` (`Registry` CHAR(72) NOT NULL, `Root` INTEGER NOT NULL, `Key` CHAR(255) NOT NULL, `Name` CHAR(255), `Value` CHAR(0), `Component_` CHAR(72) NOT NULL PRIMARY KEY `Registry`)',
            'CREATE TABLE `CustomAction` (`Action` CHAR(72) NOT NULL, `Type` INTEGER NOT NULL, `Source` CHAR(72), `Target` CHAR(255) PRIMARY KEY `Action`)',
            'CREATE TABLE `Binary` (`Name` CHAR(72) NOT NULL, `Data` OBJECT NOT NULL PRIMARY KEY `Name`)',
            'CREATE TABLE `Media` (`DiskId` INTEGER NOT NULL, `LastSequence` LONG NOT NULL, `DiskPrompt` CHAR(64), `Cabinet` CHAR(255), `VolumeLabel` CHAR(32), `Source` CHAR(72) PRIMARY KEY `DiskId`)',
            # VersionMin/VersionMax are part of the primary key here, which is what -SignificantOnly has to cope with.
            'CREATE TABLE `Upgrade` (`UpgradeCode` CHAR(38) NOT NULL, `VersionMin` CHAR(20), `VersionMax` CHAR(20), `Language` CHAR(255), `Attributes` LONG NOT NULL, `Remove` CHAR(255), `ActionProperty` CHAR(72) NOT NULL PRIMARY KEY `UpgradeCode`, `VersionMin`, `VersionMax`, `Language`, `Attributes`)'
        )
        if ($SecondRevision) {
            $schema += 'CREATE TABLE `LaunchCondition` (`Condition` CHAR(255) NOT NULL, `Description` CHAR(255) NOT NULL PRIMARY KEY `Condition`)'
        }
        foreach ($sql in $schema) { Invoke-MsiSql -Database $database -Sql $sql }

        $properties = [ordered]@{
            'ProductName'     = $ProductName
            'ProductVersion'  = $ProductVersion
            'ProductCode'     = $ProductCode
            'UpgradeCode'     = '{6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111}'
            'Manufacturer'    = 'Contoso Ltd'
            'ProductLanguage' = '1033'
            'ALLUSERS'        = '1'
        }
        if ($SecondRevision) {
            $properties['REBOOT'] = 'ReallySuppress'
            $properties['Manufacturer'] = 'Contoso International Ltd'
        } else {
            $properties['LEGACYMODE'] = '1'
        }
        foreach ($name in $properties.Keys) {
            Add-MsiRow -Installer $installer -Database $database -Table 'Property' -Values @{ 'Property' = $name; 'Value' = $properties[$name] }
        }

        Add-MsiRow $installer $database 'Directory' @{ 'Directory' = 'TARGETDIR'; 'Directory_Parent' = $null; 'DefaultDir' = 'SourceDir' }
        Add-MsiRow $installer $database 'Directory' @{ 'Directory' = 'ProgramFilesFolder'; 'Directory_Parent' = 'TARGETDIR'; 'DefaultDir' = '.' }
        Add-MsiRow $installer $database 'Directory' @{ 'Directory' = 'CompanyFolder'; 'Directory_Parent' = 'ProgramFilesFolder'; 'DefaultDir' = 'Contoso' }
        Add-MsiRow $installer $database 'Directory' @{ 'Directory' = 'INSTALLDIR'; 'Directory_Parent' = 'CompanyFolder'; 'DefaultDir' = 'DemoApp' }

        Add-MsiRow $installer $database 'Component' @{ 'Component' = 'MainExe'; 'ComponentId' = '{11111111-1111-1111-1111-111111111111}'; 'Directory_' = 'INSTALLDIR'; 'Attributes' = 0; 'KeyPath' = 'app.exe' }
        Add-MsiRow $installer $database 'Component' @{ 'Component' = 'Docs'; 'ComponentId' = '{22222222-2222-2222-2222-222222222222}'; 'Directory_' = 'INSTALLDIR'; 'Attributes' = 0; 'KeyPath' = 'readme.txt' }
        if ($SecondRevision) {
            Add-MsiRow $installer $database 'Component' @{ 'Component' = 'Plugin'; 'ComponentId' = '{33333333-3333-3333-3333-333333333333}'; 'Directory_' = 'INSTALLDIR'; 'Attributes' = 0; 'KeyPath' = 'plugin.dll' }
        }

        Add-MsiRow $installer $database 'Feature' @{ 'Feature' = 'Complete'; 'Title' = 'Complete'; 'Level' = 1; 'Attributes' = 0; 'Display' = 1 }
        Add-MsiRow $installer $database 'FeatureComponents' @{ 'Feature_' = 'Complete'; 'Component_' = 'MainExe' }
        Add-MsiRow $installer $database 'FeatureComponents' @{ 'Feature_' = 'Complete'; 'Component_' = 'Docs' }
        if ($SecondRevision) {
            Add-MsiRow $installer $database 'FeatureComponents' @{ 'Feature_' = 'Complete'; 'Component_' = 'Plugin' }
        }

        $exeVersion = '1.0.0.0'
        $exeSize = 204800
        if ($SecondRevision) {
            $exeVersion = '1.1.0.0'
            $exeSize = 215040
        }
        Add-MsiRow $installer $database 'File' @{ 'File' = 'app.exe'; 'Component_' = 'MainExe'; 'FileName' = 'app.exe'; 'FileSize' = $exeSize; 'Version' = $exeVersion; 'Language' = '1033'; 'Attributes' = 512; 'Sequence' = 1 }
        Add-MsiRow $installer $database 'File' @{ 'File' = 'readme.txt'; 'Component_' = 'Docs'; 'FileName' = 'readme.txt'; 'FileSize' = 2048; 'Attributes' = 512; 'Sequence' = 2 }
        if ($SecondRevision) {
            Add-MsiRow $installer $database 'File' @{ 'File' = 'plugin.dll'; 'Component_' = 'Plugin'; 'FileName' = 'plugin.dll'; 'FileSize' = 51200; 'Version' = '1.1.0.0'; 'Language' = '1033'; 'Attributes' = 512; 'Sequence' = 3 }
        } else {
            Add-MsiRow $installer $database 'File' @{ 'File' = 'legacy.dll'; 'Component_' = 'MainExe'; 'FileName' = 'legacy.dll'; 'FileSize' = 33792; 'Version' = '1.0.0.0'; 'Language' = '1033'; 'Attributes' = 512; 'Sequence' = 3 }
        }

        $hashSeed = 1
        if ($SecondRevision) { $hashSeed = 7 }
        Add-MsiRow $installer $database 'MsiFileHash' @{ 'File_' = 'app.exe'; 'Options' = 0; 'HashPart1' = (1000 * $hashSeed); 'HashPart2' = (2000 * $hashSeed); 'HashPart3' = (3000 * $hashSeed); 'HashPart4' = (4000 * $hashSeed) }
        Add-MsiRow $installer $database 'MsiFileHash' @{ 'File_' = 'readme.txt'; 'Options' = 0; 'HashPart1' = 11; 'HashPart2' = 22; 'HashPart3' = 33; 'HashPart4' = 44 }

        Add-MsiRow $installer $database 'Registry' @{ 'Registry' = 'RegInstallDir'; 'Root' = 2; 'Key' = 'SOFTWARE\Contoso\DemoApp'; 'Name' = 'InstallDir'; 'Value' = '[INSTALLDIR]'; 'Component_' = 'MainExe' }
        Add-MsiRow $installer $database 'Registry' @{ 'Registry' = 'RegVersion'; 'Root' = 2; 'Key' = 'SOFTWARE\Contoso\DemoApp'; 'Name' = 'Version'; 'Value' = $ProductVersion; 'Component_' = 'MainExe' }
        if (-not $SecondRevision) {
            Add-MsiRow $installer $database 'Registry' @{ 'Registry' = 'RegLegacy'; 'Root' = 2; 'Key' = 'SOFTWARE\Contoso\DemoApp'; 'Name' = 'LegacyMode'; 'Value' = '1'; 'Component_' = 'MainExe' }
        }

        Add-MsiRow $installer $database 'CustomAction' @{ 'Action' = 'SetInstallDir'; 'Type' = 51; 'Source' = 'INSTALLDIR'; 'Target' = '[ProgramFilesFolder]Contoso\DemoApp' }
        if ($SecondRevision) {
            Add-MsiRow $installer $database 'CustomAction' @{ 'Action' = 'RegisterPlugin'; 'Type' = 1; 'Source' = 'Setup'; 'Target' = 'RegisterPluginEntry' }
        }

        # Two rows in the shape WiX MajorUpgrade emits: they differ only by Attributes once
        # the version bounds are ignored, which is what keeps the reduced key unambiguous.
        $currentVersion = '1.0.0'
        if ($SecondRevision) { $currentVersion = '1.1.0' }
        Add-MsiRow $installer $database 'Upgrade' @{
            'UpgradeCode'    = '{6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111}'
            'VersionMax'     = $currentVersion
            'Attributes'     = 256
            'ActionProperty' = 'WIX_UPGRADE_DETECTED'
        }
        Add-MsiRow $installer $database 'Upgrade' @{
            'UpgradeCode'    = '{6B1F4B0E-6C8D-4E6A-9D0E-2F3C3B8A1111}'
            'VersionMin'     = $currentVersion
            'Attributes'     = 2
            'ActionProperty' = 'WIX_DOWNGRADE_DETECTED'
        }

        Add-MsiRow $installer $database 'Binary' @{ 'Name' = 'Setup'; 'Data' = @{ 'StreamFile' = $binaryFile } }
        Add-MsiRow $installer $database 'Media' @{ 'DiskId' = 1; 'LastSequence' = 3; 'Cabinet' = 'product.cab' }

        if ($SecondRevision) {
            Add-MsiRow $installer $database 'LaunchCondition' @{ 'Condition' = 'VersionNT >= 601'; 'Description' = 'Windows 7 or newer is required.' }
        }

        $null = Invoke-MsiMethod $database 'Commit'
    } finally {
        if ($null -ne $database) { Remove-MsiComObject $database }
        Remove-MsiComObject $installer
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Remove-Item -LiteralPath $binaryFile -Force -ErrorAction SilentlyContinue
    }

    $installer = New-MsiInstaller
    try {
        $summary = Get-MsiComProperty $installer 'SummaryInformation' @($Path, 20)
        Set-MsiComProperty $summary 'Property' @(1, 1252)
        Set-MsiComProperty $summary 'Property' @(2, 'Installation Database')
        Set-MsiComProperty $summary 'Property' @(3, $ProductName)
        Set-MsiComProperty $summary 'Property' @(4, 'Contoso Ltd')
        Set-MsiComProperty $summary 'Property' @(5, 'Installer,MSI,Database')
        Set-MsiComProperty $summary 'Property' @(6, "Test package $ProductName $ProductVersion")
        Set-MsiComProperty $summary 'Property' @(7, $(if ($SecondRevision) { 'x64;1033' } else { 'Intel;1033' }))
        Set-MsiComProperty $summary 'Property' @(9, $PackageCode)
        Set-MsiComProperty $summary 'Property' @(14, 200)
        Set-MsiComProperty $summary 'Property' @(15, 2)
        Set-MsiComProperty $summary 'Property' @(18, 'msi-diff test generator')
        Set-MsiComProperty $summary 'Property' @(19, 0)
        $null = Invoke-MsiMethod $summary 'Persist'
        Remove-MsiComObject $summary
    } finally {
        Remove-MsiComObject $installer
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    (Resolve-Path -LiteralPath $Path).ProviderPath
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath

$first = New-TestMsi -Path (Join-Path $OutputDirectory 'DemoApp-1.0.msi') `
    -ProductName 'Demo App' -ProductVersion '1.0.0' `
    -ProductCode '{A1111111-1111-1111-1111-111111111111}' `
    -PackageCode '{B1111111-1111-1111-1111-111111111111}' `
    -BinaryPayload 'setup payload version one'

$second = New-TestMsi -Path (Join-Path $OutputDirectory 'DemoApp-1.1.msi') `
    -ProductName 'Demo App' -ProductVersion '1.1.0' `
    -ProductCode '{A2222222-2222-2222-2222-222222222222}' `
    -PackageCode '{B2222222-2222-2222-2222-222222222222}' `
    -BinaryPayload 'setup payload version two, slightly longer' -SecondRevision

Write-Host "Created:"
Write-Host "  $first"
Write-Host "  $second"
[pscustomobject]@{ Reference = $first; Difference = $second }
