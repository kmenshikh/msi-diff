<#
.SYNOPSIS
    Compares two MSI packages and writes a report in HTML and/or Markdown.

.DESCRIPTION
    Opens both Windows Installer databases through the msi.dll API, reads the Summary
    Information Stream and every table, then compares them row by row using the primary
    key of each table. On top of that a flattened view of the installed files is built
    (File + Component + Directory + MsiFileHash).

    No external dependencies: only what already ships with Windows is used.

.PARAMETER ReferenceMsi
    The original ("old") package - the left-hand side of the comparison.

.PARAMETER DifferenceMsi
    The new package - the right-hand side of the comparison.

.PARAMETER HtmlReport
    Path to the HTML report. When neither -HtmlReport nor -MarkdownReport is given,
    .\msi-diff.html is used.

.PARAMETER MarkdownReport
    Path to the Markdown report.

.PARAMETER IncludeTable
    Compare only these tables. Wildcards are supported: Msi*, Custom*.

.PARAMETER ExcludeTable
    Exclude tables from the comparison. Wildcards are supported.

.PARAMETER IgnoreProperty
    Names of Property table entries whose differences are not taken into account.

.PARAMETER IgnoreBuildNoise
    Ignore the differences every rebuild produces: PackageCode, ProductCode,
    timestamps, the name of the build account and CreatingApplication.

.PARAMETER SignificantOnly
    Significant changes only. The following are not taken into account:
      * file size       - File.FileSize and the Size column of the file view;
      * file version    - File.Version and the Version column of the file view;
      * checksum        - MsiFileHash.HashPart1..4 and the MD5 column of the file view;
      * upgrade version bounds - Upgrade.VersionMin and Upgrade.VersionMax;
      * product identity       - the ProductCode and ProductVersion properties;
      * package description    - the Comments field of the Summary Information Stream.
    Added, removed and moved files are still reported, as are changes to components,
    the registry, properties and sequences.

.PARAMETER MaxRowsPerTable
    Maximum number of differing rows per table in the reports. 0 means unlimited.

.PARAMETER NoStreamHash
    Do not hash binary streams (Binary, Icon). Faster, but a change inside a stream
    of the same size goes unnoticed.

.PARAMETER ShowUnchanged
    Include identical rows and tables in the reports.

.PARAMETER OpenReport
    Open the HTML report once it has been written.

.PARAMETER PassThru
    Emit the comparison result object to the pipeline.

.PARAMETER Quiet
    Do not print the summary to the console.

.OUTPUTS
    Exit codes: 0 - packages are identical, 1 - differences found, 2 - error.

.EXAMPLE
    .\Compare-Msi.ps1 .\app-1.0.msi .\app-1.1.msi

.EXAMPLE
    .\Compare-Msi.ps1 -ReferenceMsi old.msi -DifferenceMsi new.msi `
        -HtmlReport .\out\diff.html -MarkdownReport .\out\diff.md -IgnoreBuildNoise -OpenReport

.EXAMPLE
    .\Compare-Msi.ps1 old.msi new.msi -IncludeTable File,Component,Registry -MaxRowsPerTable 0

.EXAMPLE
    .\Compare-Msi.ps1 old.msi new.msi -SignificantOnly -IgnoreBuildNoise -MarkdownReport diff.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $ReferenceMsi,

    [Parameter(Mandatory = $true, Position = 1)]
    [string] $DifferenceMsi,

    [string] $HtmlReport,
    [string] $MarkdownReport,
    [string[]] $IncludeTable,
    [string[]] $ExcludeTable,
    [string[]] $IgnoreProperty = @(),
    [switch] $IgnoreBuildNoise,
    [switch] $SignificantOnly,
    [int] $MaxRowsPerTable = 500,
    [switch] $NoStreamHash,
    [switch] $ShowUnchanged,
    [switch] $OpenReport,
    [switch] $PassThru,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'src\MsiNative.ps1')
. (Join-Path $PSScriptRoot 'src\MsiReader.ps1')
. (Join-Path $PSScriptRoot 'src\MsiDiff.ps1')
. (Join-Path $PSScriptRoot 'src\ReportHtml.ps1')
. (Join-Path $PSScriptRoot 'src\ReportMarkdown.ps1')
. (Join-Path $PSScriptRoot 'src\ReportConsole.ps1')

# powershell.exe -File passes "A,B" as a single string, so list arguments coming through
# msi-diff.cmd have to be split by hand. Table and property names cannot contain commas.
function Expand-ListArgument {
    param([string[]] $Values)
    if (-not $Values) { return @() }
    @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
}

function Resolve-InputPath {
    param([string] $Path, [string] $Label)
    $resolved = $null
    try { $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { }
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "${Label}: file not found - '$Path'"
    }
    $resolved
}

function Resolve-OutputPath {
    param([string] $Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $Path))
}

try {
    $referencePath = Resolve-InputPath -Path $ReferenceMsi -Label 'ReferenceMsi'
    $differencePath = Resolve-InputPath -Path $DifferenceMsi -Label 'DifferenceMsi'

    $IncludeTable = Expand-ListArgument $IncludeTable
    $ExcludeTable = Expand-ListArgument $ExcludeTable
    $IgnoreProperty = Expand-ListArgument $IgnoreProperty

    if (-not $HtmlReport -and -not $MarkdownReport) { $HtmlReport = '.\msi-diff.html' }

    $progress = {
        param($package, $table, $index, $total)
        Write-Progress -Activity "Reading $package" -Status "Table $table" -PercentComplete ([int](100 * $index / [Math]::Max($total, 1)))
    }
    if ($Quiet) { $progress = $null }

    $reference = Read-MsiPackage -Path $referencePath -IncludeTable $IncludeTable -ExcludeTable $ExcludeTable `
        -NoStreamHash:$NoStreamHash -OnProgress $progress
    $difference = Read-MsiPackage -Path $differencePath -IncludeTable $IncludeTable -ExcludeTable $ExcludeTable `
        -NoStreamHash:$NoStreamHash -OnProgress $progress
    Write-Progress -Activity 'Reading MSI' -Completed

    $diff = Compare-MsiPackageData -Reference $reference -Difference $difference `
        -IgnoreProperty $IgnoreProperty -IgnoreBuildNoise:$IgnoreBuildNoise -SignificantOnly:$SignificantOnly

    $written = New-Object System.Collections.Generic.List[string]
    if ($HtmlReport) {
        $path = Resolve-OutputPath $HtmlReport
        $null = New-MsiHtmlReport -Diff $diff -Path $path -MaxRows $MaxRowsPerTable -ShowUnchanged:$ShowUnchanged
        $written.Add($path)
    }
    if ($MarkdownReport) {
        $path = Resolve-OutputPath $MarkdownReport
        $null = New-MsiMarkdownReport -Diff $diff -Path $path -MaxRows $MaxRowsPerTable -ShowUnchanged:$ShowUnchanged
        $written.Add($path)
    }

    if (-not $Quiet) {
        Write-MsiConsoleSummary -Diff $diff
        foreach ($path in $written) { Write-Host ('  report: {0}' -f $path) -ForegroundColor Cyan }
        Write-Host ''
    }

    if ($OpenReport -and $HtmlReport) {
        Start-Process (Resolve-OutputPath $HtmlReport)
    }

    if ($PassThru) { $diff }

    exit $(if ($diff.IsIdentical) { 0 } else { 1 })
} catch {
    Write-Host ''
    Write-Host ('Error: {0}' -f $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) { Write-Verbose $_.ScriptStackTrace }
    exit 2
}
