# Diff engine: compares two package snapshots produced by Read-MsiPackage.

$ErrorActionPreference = 'Stop'

$script:NullToken = [string][char]1 + 'NULL'
$script:KeySeparator = [string][char]31

$script:BuildNoiseSummaryKeys = @(
    'PackageCode', 'CreateTime', 'LastSavedTime', 'LastSavedBy', 'CreatingApplication'
)
$script:BuildNoiseProperties = @(
    'ProductCode', 'PackageCode'
)

# -SignificantOnly: columns that carry version or payload detail rather than package
# structure. Ignoring them hides rebuilds but keeps added, removed and moved entries.
# VersionMin/VersionMax belong to the primary key of Upgrade, so they are dropped from
# the matching key as well - otherwise a changed range would still show up as a pair of
# removed and added rows.
$script:SignificantOnlyColumns = @{
    'File'        = @('FileSize', 'Version')
    'MsiFileHash' = @('HashPart1', 'HashPart2', 'HashPart3', 'HashPart4')
    'Upgrade'     = @('VersionMin', 'VersionMax')
}
$script:SignificantOnlyFileViewColumns = @('Size', 'Version', 'MD5')

# Whole rows dropped from a table, matched by primary key value.
$script:SignificantOnlyProperties = @('ProductCode', 'ProductVersion')
$script:SignificantOnlyRows = @{
    'Property' = $script:SignificantOnlyProperties
}

# Comments usually just restates the product version, so it changes on every release.
$script:SignificantOnlySummaryKeys = @('Comments')

function ConvertTo-MsiCompareToken {
    param($Value)
    if ($null -eq $Value) { return $script:NullToken }
    [string]$Value
}

function ConvertTo-MsiDisplayValue {
    param($Value)
    if ($null -eq $Value) { return '(null)' }
    $text = [string]$Value
    if ($text.Length -eq 0) { return '(empty)' }
    $text
}

function Get-MsiRowKey {
    param([hashtable] $Row, [string[]] $KeyColumns)
    # Conversion is inlined: this runs once per row of every table.
    $parts = foreach ($column in $KeyColumns) {
        $value = $Row[$column]
        if ($null -eq $value) { $script:NullToken } else { [string]$value }
    }
    $parts -join $script:KeySeparator
}

function Compare-MsiSummary {
    param(
        [Parameter(Mandatory = $true)] $Reference,
        [Parameter(Mandatory = $true)] $Difference,
        [string[]] $IgnoreKeys = @()
    )

    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Reference.Summary.Keys) { if (-not $keys.Contains($key)) { $keys.Add($key) } }
    foreach ($key in $Difference.Summary.Keys) { if (-not $keys.Contains($key)) { $keys.Add($key) } }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($key in $keys) {
        if ($IgnoreKeys -contains $key) { continue }

        $left = $null
        $right = $null
        if ($Reference.Summary.Contains($key)) { $left = $Reference.Summary[$key] }
        if ($Difference.Summary.Contains($key)) { $right = $Difference.Summary[$key] }

        $same = (ConvertTo-MsiCompareToken $left) -ceq (ConvertTo-MsiCompareToken $right)
        $rows.Add([pscustomobject]@{
            Name       = $key
            Reference  = ConvertTo-MsiDisplayValue $left
            Difference = ConvertTo-MsiDisplayValue $right
            Status     = $(if ($same) { 'Identical' } else { 'Changed' })
        })
    }

    , $rows.ToArray()
}

function Compare-MsiTableRows {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        $ReferenceTable,
        $DifferenceTable,
        [string[]] $IgnoreColumns = @(),
        [string[]] $IgnoreRowKeys = @()
    )

    $refColumns = @()
    $diffColumns = @()
    if ($ReferenceTable) { $refColumns = @($ReferenceTable.Columns) }
    if ($DifferenceTable) { $diffColumns = @($DifferenceTable.Columns) }

    $columns = New-Object System.Collections.Generic.List[string]
    foreach ($column in $refColumns) { if (-not $columns.Contains($column)) { $columns.Add($column) } }
    foreach ($column in $diffColumns) { if (-not $columns.Contains($column)) { $columns.Add($column) } }

    $keyColumns = @()
    if ($ReferenceTable -and @($ReferenceTable.PrimaryKeys).Count -gt 0) { $keyColumns = @($ReferenceTable.PrimaryKeys) }
    elseif ($DifferenceTable -and @($DifferenceTable.PrimaryKeys).Count -gt 0) { $keyColumns = @($DifferenceTable.PrimaryKeys) }
    if ($keyColumns.Count -eq 0) { $keyColumns = $columns.ToArray() }

    # An ignored column must not keep rows apart either, or the change it describes would
    # merely turn into a removed/added pair. The key is only reduced while something is left.
    if ($IgnoreColumns.Count -gt 0) {
        $reducedKey = @($keyColumns | Where-Object { $IgnoreColumns -notcontains $_ })
        if ($reducedKey.Count -gt 0) { $keyColumns = $reducedKey }
    }

    $comparableColumns = @($columns | Where-Object {
        ($refColumns -contains $_) -and ($diffColumns -contains $_) -and ($IgnoreColumns -notcontains $_)
    })
    $ignoredColumns = @($columns | Where-Object { $IgnoreColumns -contains $_ })

    $refRows = Get-MsiKeyedRows -Table $ReferenceTable -KeyColumns $keyColumns -IgnoreKeys $IgnoreRowKeys
    $diffRows = Get-MsiKeyedRows -Table $DifferenceTable -KeyColumns $keyColumns -IgnoreKeys $IgnoreRowKeys

    $added = New-Object System.Collections.Generic.List[object]
    $removed = New-Object System.Collections.Generic.List[object]
    $changed = New-Object System.Collections.Generic.List[object]
    $unchanged = 0

    foreach ($key in @($refRows.Keys)) {
        if ($diffRows.Contains($key)) {
            $left = $refRows[$key]
            $right = $diffRows[$key]
            $changedColumns = New-Object System.Collections.Generic.List[string]
            # Hot loop: runs for every column of every matched row, so no helper calls here.
            foreach ($column in $comparableColumns) {
                $a = $left[$column]
                $b = $right[$column]
                if ($null -eq $a) {
                    if ($null -ne $b) { $changedColumns.Add($column) }
                } elseif ($null -eq $b -or ([string]$a -cne [string]$b)) {
                    $changedColumns.Add($column)
                }
            }
            if ($changedColumns.Count -gt 0) {
                $changed.Add([pscustomobject]@{
                    Key            = $key
                    Reference      = $left
                    Difference     = $right
                    ChangedColumns = $changedColumns.ToArray()
                })
            } else {
                $unchanged++
            }
        } else {
            $removed.Add($refRows[$key])
        }
    }
    foreach ($key in @($diffRows.Keys)) {
        if (-not $refRows.Contains($key)) { $added.Add($diffRows[$key]) }
    }

    $status = 'Identical'
    if ($null -eq $ReferenceTable) { $status = 'Added' }
    elseif ($null -eq $DifferenceTable) { $status = 'Removed' }
    elseif ($added.Count -or $removed.Count -or $changed.Count) { $status = 'Changed' }

    [pscustomobject]@{
        Name                    = $Name
        Status                  = $status
        Columns                 = $columns.ToArray()
        KeyColumns              = $keyColumns
        AddedRows               = $added.ToArray()
        RemovedRows             = $removed.ToArray()
        ChangedRows             = $changed.ToArray()
        UnchangedCount          = $unchanged
        IgnoredColumns          = $ignoredColumns
        IgnoredRowKeys          = @($IgnoreRowKeys)
        ReferenceRowCount       = $refRows.Count
        DifferenceRowCount      = $diffRows.Count
        # Only meaningful when both sides have the table; otherwise every column would be listed.
        ColumnsOnlyInReference  = @(if ($ReferenceTable -and $DifferenceTable) { $refColumns | Where-Object { $diffColumns -notcontains $_ } })
        ColumnsOnlyInDifference = @(if ($ReferenceTable -and $DifferenceTable) { $diffColumns | Where-Object { $refColumns -notcontains $_ } })
    }
}

function Get-MsiKeyedRows {
    param($Table, [string[]] $KeyColumns, [string[]] $IgnoreKeys = @())

    $map = New-Object System.Collections.Specialized.OrderedDictionary
    if ($null -eq $Table) { return $map }

    foreach ($row in $Table.Rows) {
        $key = Get-MsiRowKey -Row $row -KeyColumns $KeyColumns
        if ($IgnoreKeys.Count -gt 0 -and $IgnoreKeys -contains $key) { continue }
        if ($map.Contains($key)) {
            $suffix = 2
            while ($map.Contains("$key#$suffix")) { $suffix++ }
            $key = "$key#$suffix"
        }
        $map[$key] = $row
    }
    $map
}

function Resolve-MsiDirectoryPaths {
    param($Package)

    $paths = @{}
    if (-not $Package.Tables.Contains('Directory')) { return $paths }

    $entries = @{}
    foreach ($row in $Package.Tables['Directory'].Rows) {
        $entries[[string]$row['Directory']] = @{
            Parent     = $row['Directory_Parent']
            DefaultDir = [string]$row['DefaultDir']
        }
    }

    foreach ($key in $entries.Keys) {
        $null = Resolve-MsiDirectoryPath -Key $key -Entries $entries -Cache $paths -Depth 0
    }
    $paths
}

function Resolve-MsiDirectoryPath {
    param([string] $Key, [hashtable] $Entries, [hashtable] $Cache, [int] $Depth)

    if ($Cache.ContainsKey($Key)) { return $Cache[$Key] }
    if ($Depth -gt 64 -or -not $Entries.ContainsKey($Key)) { return $Key }

    $Cache[$Key] = $Key  # cycle guard

    $entry = $Entries[$Key]
    $parent = $entry.Parent
    $segment = Get-MsiLongDirectoryName -DefaultDir $entry.DefaultDir

    if ([string]::IsNullOrEmpty([string]$parent) -or [string]$parent -eq $Key) {
        $path = $Key
    } else {
        $parentPath = Resolve-MsiDirectoryPath -Key ([string]$parent) -Entries $Entries -Cache $Cache -Depth ($Depth + 1)
        if ($segment -eq '.' -or [string]::IsNullOrEmpty($segment)) {
            $path = $parentPath + '\' + $Key
        } else {
            $path = $parentPath + '\' + $segment
        }
    }

    $Cache[$Key] = $path
    $path
}

function Get-MsiLongDirectoryName {
    param([string] $DefaultDir)
    if ([string]::IsNullOrEmpty($DefaultDir)) { return '' }
    $target = $DefaultDir.Split(':')[0]
    $parts = $target.Split('|')
    $parts[$parts.Count - 1]
}

function Get-MsiLongFileName {
    param([string] $FileName)
    if ([string]::IsNullOrEmpty($FileName)) { return '' }
    $parts = $FileName.Split('|')
    $parts[$parts.Count - 1]
}

function ConvertTo-MsiFileHashString {
    param($Part1, $Part2, $Part3, $Part4)
    $bytes = New-Object System.Collections.Generic.List[byte]
    foreach ($part in @($Part1, $Part2, $Part3, $Part4)) {
        if ($null -eq $part) { return $null }
        foreach ($b in [System.BitConverter]::GetBytes([int]$part)) { $bytes.Add($b) }
    }
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

# Flattens File + Component + Directory + MsiFileHash into "what actually lands on disk".
function Get-MsiFileView {
    param($Package)

    $view = New-Object System.Collections.Specialized.OrderedDictionary
    if (-not $Package.Tables.Contains('File')) { return $view }

    $directoryPaths = Resolve-MsiDirectoryPaths -Package $Package

    $components = @{}
    if ($Package.Tables.Contains('Component')) {
        foreach ($row in $Package.Tables['Component'].Rows) {
            $components[[string]$row['Component']] = $row
        }
    }

    $hashes = @{}
    if ($Package.Tables.Contains('MsiFileHash')) {
        foreach ($row in $Package.Tables['MsiFileHash'].Rows) {
            $hashes[[string]$row['File_']] = ConvertTo-MsiFileHashString $row['HashPart1'] $row['HashPart2'] $row['HashPart3'] $row['HashPart4']
        }
    }

    foreach ($row in $Package.Tables['File'].Rows) {
        $fileKey = [string]$row['File']
        $componentKey = [string]$row['Component_']

        $directoryKey = ''
        $componentId = $null
        if ($components.ContainsKey($componentKey)) {
            $directoryKey = [string]$components[$componentKey]['Directory_']
            $componentId = $components[$componentKey]['ComponentId']
        }

        $directoryPath = $directoryKey
        if ($directoryPaths.ContainsKey($directoryKey)) { $directoryPath = $directoryPaths[$directoryKey] }

        $targetPath = $directoryPath + '\' + (Get-MsiLongFileName ([string]$row['FileName']))

        $entry = @{
            'TargetPath' = $targetPath
            'File'       = $fileKey
            'Version'    = $row['Version']
            'Size'       = $row['FileSize']
            'Language'   = $row['Language']
            'Attributes' = $row['Attributes']
            'Sequence'   = $row['Sequence']
            'Component'  = $componentKey
            'ComponentId' = $componentId
            'MD5'        = $(if ($hashes.ContainsKey($fileKey)) { $hashes[$fileKey] } else { $null })
        }

        $key = $targetPath.ToLowerInvariant()
        if ($view.Contains($key)) { $key = $key + '#' + $fileKey }
        $view[$key] = $entry
    }
    $view
}

function Compare-MsiFileView {
    param($Reference, $Difference, [string[]] $IgnoreColumns = @())

    $columns = @('TargetPath', 'Version', 'Size', 'MD5', 'Language', 'Attributes', 'Sequence', 'Component', 'ComponentId')
    $comparableColumns = @($columns | Where-Object { $IgnoreColumns -notcontains $_ })
    $ignoredColumns = @($columns | Where-Object { $IgnoreColumns -contains $_ })

    $left = Get-MsiFileView -Package $Reference
    $right = Get-MsiFileView -Package $Difference

    $added = New-Object System.Collections.Generic.List[object]
    $removed = New-Object System.Collections.Generic.List[object]
    $changed = New-Object System.Collections.Generic.List[object]
    $unchanged = 0

    foreach ($key in $left.Keys) {
        if ($right.Contains($key)) {
            $leftRow = $left[$key]
            $rightRow = $right[$key]
            $changedColumns = New-Object System.Collections.Generic.List[string]
            foreach ($column in $comparableColumns) {
                $a = $leftRow[$column]
                $b = $rightRow[$column]
                if ($null -eq $a) {
                    if ($null -ne $b) { $changedColumns.Add($column) }
                } elseif ($null -eq $b -or ([string]$a -cne [string]$b)) {
                    $changedColumns.Add($column)
                }
            }
            if ($changedColumns.Count -gt 0) {
                $changed.Add([pscustomobject]@{
                    Key            = $key
                    Reference      = $leftRow
                    Difference     = $rightRow
                    ChangedColumns = $changedColumns.ToArray()
                })
            } else {
                $unchanged++
            }
        } else {
            $removed.Add($left[$key])
        }
    }
    foreach ($key in $right.Keys) {
        if (-not $left.Contains($key)) { $added.Add($right[$key]) }
    }

    [pscustomobject]@{
        Name                    = 'Files'
        Status                  = $(if ($added.Count -or $removed.Count -or $changed.Count) { 'Changed' } else { 'Identical' })
        Columns                 = $columns
        KeyColumns              = @('TargetPath')
        AddedRows               = $added.ToArray()
        RemovedRows             = $removed.ToArray()
        ChangedRows             = $changed.ToArray()
        UnchangedCount          = $unchanged
        IgnoredColumns          = $ignoredColumns
        IgnoredRowKeys          = @()
        ReferenceRowCount       = $left.Count
        DifferenceRowCount      = $right.Count
        ColumnsOnlyInReference  = @()
        ColumnsOnlyInDifference = @()
    }
}

function Compare-MsiPropertyView {
    param($Reference, $Difference, [string[]] $IgnoreProperty = @())

    $left = @{}
    $right = @{}
    if ($Reference.Tables.Contains('Property')) {
        foreach ($row in $Reference.Tables['Property'].Rows) { $left[[string]$row['Property']] = $row['Value'] }
    }
    if ($Difference.Tables.Contains('Property')) {
        foreach ($row in $Difference.Tables['Property'].Rows) { $right[[string]$row['Property']] = $row['Value'] }
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in $left.Keys) { if (-not $names.Contains($name)) { $names.Add($name) } }
    foreach ($name in $right.Keys) { if (-not $names.Contains($name)) { $names.Add($name) } }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in ($names | Sort-Object)) {
        if ($IgnoreProperty -contains $name) { continue }

        $inLeft = $left.ContainsKey($name)
        $inRight = $right.ContainsKey($name)
        $status = 'Identical'
        if (-not $inLeft) { $status = 'Added' }
        elseif (-not $inRight) { $status = 'Removed' }
        elseif ((ConvertTo-MsiCompareToken $left[$name]) -cne (ConvertTo-MsiCompareToken $right[$name])) { $status = 'Changed' }

        $rows.Add([pscustomobject]@{
            Name       = $name
            Reference  = $(if ($inLeft) { ConvertTo-MsiDisplayValue $left[$name] } else { '' })
            Difference = $(if ($inRight) { ConvertTo-MsiDisplayValue $right[$name] } else { '' })
            Status     = $status
        })
    }

    , $rows.ToArray()
}

function Compare-MsiPackageData {
    param(
        [Parameter(Mandatory = $true)] $Reference,
        [Parameter(Mandatory = $true)] $Difference,
        [string[]] $IgnoreProperty = @(),
        [switch] $IgnoreBuildNoise,
        [switch] $SignificantOnly
    )

    $ignoredSummaryKeys = @()
    $ignoredProperties = @($IgnoreProperty)
    if ($IgnoreBuildNoise) {
        $ignoredSummaryKeys += $script:BuildNoiseSummaryKeys
        $ignoredProperties += $script:BuildNoiseProperties
    }

    $ignoredColumnsByTable = @{}
    $ignoredRowsByTable = @{}
    $ignoredFileViewColumns = @()
    if ($SignificantOnly) {
        $ignoredColumnsByTable = $script:SignificantOnlyColumns
        $ignoredRowsByTable = $script:SignificantOnlyRows
        $ignoredFileViewColumns = $script:SignificantOnlyFileViewColumns
        $ignoredProperties += $script:SignificantOnlyProperties
        $ignoredSummaryKeys += $script:SignificantOnlySummaryKeys
    }

    $summaryDiff = Compare-MsiSummary -Reference $Reference -Difference $Difference -IgnoreKeys $ignoredSummaryKeys
    $propertyDiff = Compare-MsiPropertyView -Reference $Reference -Difference $Difference -IgnoreProperty $ignoredProperties
    $fileDiff = Compare-MsiFileView -Reference $Reference -Difference $Difference -IgnoreColumns $ignoredFileViewColumns

    $tableNames = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Reference.Tables.Keys) { if (-not $tableNames.Contains($name)) { $tableNames.Add($name) } }
    foreach ($name in $Difference.Tables.Keys) { if (-not $tableNames.Contains($name)) { $tableNames.Add($name) } }

    $tableDiffs = New-Object System.Collections.Generic.List[object]
    foreach ($name in ($tableNames | Sort-Object)) {
        $refTable = $null
        $diffTable = $null
        if ($Reference.Tables.Contains($name)) { $refTable = $Reference.Tables[$name] }
        if ($Difference.Tables.Contains($name)) { $diffTable = $Difference.Tables[$name] }

        $ignoreColumns = @()
        if ($ignoredColumnsByTable.ContainsKey($name)) { $ignoreColumns = $ignoredColumnsByTable[$name] }
        $ignoreRowKeys = @()
        if ($ignoredRowsByTable.ContainsKey($name)) { $ignoreRowKeys = $ignoredRowsByTable[$name] }

        $tableDiffs.Add((Compare-MsiTableRows -Name $name -ReferenceTable $refTable -DifferenceTable $diffTable `
            -IgnoreColumns $ignoreColumns -IgnoreRowKeys $ignoreRowKeys))
    }

    $order = @{ 'Removed' = 0; 'Added' = 1; 'Changed' = 2; 'Identical' = 3 }
    $sortedTableDiffs = @($tableDiffs | Sort-Object @{ Expression = { $order[$_.Status] } }, @{ Expression = { $_.Name } })

    $rowsAdded = 0
    $rowsRemoved = 0
    $rowsChanged = 0
    foreach ($table in $sortedTableDiffs) {
        $rowsAdded += $table.AddedRows.Count
        $rowsRemoved += $table.RemovedRows.Count
        $rowsChanged += $table.ChangedRows.Count
    }

    $stats = [pscustomobject]@{
        TablesAdded      = @($sortedTableDiffs | Where-Object { $_.Status -eq 'Added' }).Count
        TablesRemoved    = @($sortedTableDiffs | Where-Object { $_.Status -eq 'Removed' }).Count
        TablesChanged    = @($sortedTableDiffs | Where-Object { $_.Status -eq 'Changed' }).Count
        TablesIdentical  = @($sortedTableDiffs | Where-Object { $_.Status -eq 'Identical' }).Count
        RowsAdded        = $rowsAdded
        RowsRemoved      = $rowsRemoved
        RowsChanged      = $rowsChanged
        SummaryChanged   = @($summaryDiff | Where-Object { $_.Status -ne 'Identical' }).Count
        PropertiesAdded  = @($propertyDiff | Where-Object { $_.Status -eq 'Added' }).Count
        PropertiesRemoved = @($propertyDiff | Where-Object { $_.Status -eq 'Removed' }).Count
        PropertiesChanged = @($propertyDiff | Where-Object { $_.Status -eq 'Changed' }).Count
        FilesAdded       = $fileDiff.AddedRows.Count
        FilesRemoved     = $fileDiff.RemovedRows.Count
        FilesChanged     = $fileDiff.ChangedRows.Count
    }

    $identical = ($stats.SummaryChanged -eq 0) -and
                 ($stats.TablesAdded -eq 0) -and ($stats.TablesRemoved -eq 0) -and ($stats.TablesChanged -eq 0)

    # A table excluded by -IncludeTable/-ExcludeTable must not be reported as "no differences".
    $propertyCompared = $Reference.Tables.Contains('Property') -or $Difference.Tables.Contains('Property')
    $missingForFiles = @('File', 'Component', 'Directory', 'MsiFileHash') | Where-Object {
        -not ($Reference.Tables.Contains($_) -or $Difference.Tables.Contains($_))
    }

    [pscustomobject]@{
        GeneratedAt      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Reference        = $Reference
        Difference       = $Difference
        IsIdentical      = $identical
        Stats            = $stats
        SummaryDiff      = $summaryDiff
        PropertyDiff     = $propertyDiff
        FileDiff         = $fileDiff
        TableDiffs       = $sortedTableDiffs
        IgnoredSummary   = $ignoredSummaryKeys
        IgnoredProperties = @($ignoredProperties | Sort-Object -Unique)
        PropertyTableCompared = $propertyCompared
        FileViewMissingTables = @($missingForFiles)
        SignificantOnly       = [bool]$SignificantOnly
    }
}
