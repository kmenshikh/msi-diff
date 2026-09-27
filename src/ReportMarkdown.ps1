# Renders a diff result as a GitHub-flavoured Markdown file.

$ErrorActionPreference = 'Stop'

function ConvertTo-MarkdownCell {
    param($Text, [int] $MaxLength = 400)
    if ($null -eq $Text) { return '' }
    $value = [string]$Text
    if ($value.Length -eq 0) { return '' }
    if ($value.Length -gt $MaxLength) { $value = $value.Substring(0, $MaxLength) + '...' }
    $value = $value.Replace('|', '\|').Replace('`', '\`')
    $value = $value -replace '\r?\n', '<br>'
    $value
}

function Get-MarkdownStatusIcon {
    param([string] $Status)
    switch ($Status) {
        'Added'   { '+ added' }
        'Removed' { '- removed' }
        'Changed' { '~ changed' }
        default   { '= unchanged' }
    }
}

function Write-MarkdownKeyValueSection {
    param(
        [System.Text.StringBuilder] $Builder,
        [string] $Title,
        [string] $Subtitle,
        $Rows,
        [string] $ReferenceLabel,
        [string] $DifferenceLabel,
        [string] $EmptyMessage = 'No differences.',
        [switch] $ShowUnchanged
    )

    $visible = @($Rows | Where-Object { $ShowUnchanged -or $_.Status -ne 'Identical' })

    [void]$Builder.AppendLine("## $Title")
    [void]$Builder.AppendLine()
    if ($Subtitle) {
        [void]$Builder.AppendLine("_${Subtitle}_")
        [void]$Builder.AppendLine()
    }
    if ($visible.Count -eq 0) {
        if ($EmptyMessage) {
            [void]$Builder.AppendLine($EmptyMessage)
            [void]$Builder.AppendLine()
        }
        return
    }

    [void]$Builder.AppendLine("| Status | Name | $(ConvertTo-MarkdownCell $ReferenceLabel) | $(ConvertTo-MarkdownCell $DifferenceLabel) |")
    [void]$Builder.AppendLine('| --- | --- | --- | --- |')
    foreach ($row in $visible) {
        [void]$Builder.AppendLine("| $(Get-MarkdownStatusIcon $row.Status) | ``$(ConvertTo-MarkdownCell $row.Name)`` | $(ConvertTo-MarkdownCell $row.Reference) | $(ConvertTo-MarkdownCell $row.Difference) |")
    }
    [void]$Builder.AppendLine()
}

function Write-MarkdownTableDiff {
    param(
        [System.Text.StringBuilder] $Builder,
        $TableDiff,
        [int] $MaxRows,
        [switch] $Collapsed
    )

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($row in $TableDiff.RemovedRows) { $entries.Add([pscustomobject]@{ Status = 'Removed'; Row = $row; Other = $null; Changed = @() }) }
    foreach ($row in $TableDiff.AddedRows)   { $entries.Add([pscustomobject]@{ Status = 'Added'; Row = $row; Other = $null; Changed = @() }) }
    foreach ($row in $TableDiff.ChangedRows) { $entries.Add([pscustomobject]@{ Status = 'Changed'; Row = $row.Reference; Other = $row.Difference; Changed = $row.ChangedColumns }) }

    $header = "$($TableDiff.Name) - +$($TableDiff.AddedRows.Count) / -$($TableDiff.RemovedRows.Count) / ~$($TableDiff.ChangedRows.Count)"

    if ($Collapsed) {
        [void]$Builder.AppendLine('<details>')
        [void]$Builder.AppendLine("<summary><b>$header</b></summary>")
        [void]$Builder.AppendLine()
    } else {
        [void]$Builder.AppendLine("### $header")
        [void]$Builder.AppendLine()
    }

    if ($TableDiff.KeyColumns.Count) {
        [void]$Builder.AppendLine("Match key: ``$($TableDiff.KeyColumns -join ', ')``")
        [void]$Builder.AppendLine()
    }
    if ($TableDiff.IgnoredColumns.Count) {
        [void]$Builder.AppendLine("Ignored columns: ``$($TableDiff.IgnoredColumns -join ', ')``")
        [void]$Builder.AppendLine()
    }
    if ($TableDiff.IgnoredRowKeys.Count) {
        [void]$Builder.AppendLine("Ignored rows: ``$($TableDiff.IgnoredRowKeys -join ', ')``")
        [void]$Builder.AppendLine()
    }
    if ($TableDiff.ColumnsOnlyInReference.Count) {
        [void]$Builder.AppendLine("> Columns only on the left: ``$($TableDiff.ColumnsOnlyInReference -join ', ')``")
        [void]$Builder.AppendLine()
    }
    if ($TableDiff.ColumnsOnlyInDifference.Count) {
        [void]$Builder.AppendLine("> Columns only on the right: ``$($TableDiff.ColumnsOnlyInDifference -join ', ')``")
        [void]$Builder.AppendLine()
    }

    if ($entries.Count -eq 0) {
        [void]$Builder.AppendLine('No differences.')
        [void]$Builder.AppendLine()
    } else {
        $truncated = $false
        if ($MaxRows -gt 0 -and $entries.Count -gt $MaxRows) {
            $shown = $entries.GetRange(0, $MaxRows)
            $truncated = $true
        } else {
            $shown = $entries
        }

        [void]$Builder.AppendLine('| Status | ' + (($TableDiff.Columns | ForEach-Object { ConvertTo-MarkdownCell $_ }) -join ' | ') + ' |')
        [void]$Builder.AppendLine('| --- | ' + (($TableDiff.Columns | ForEach-Object { '---' }) -join ' | ') + ' |')

        foreach ($entry in $shown) {
            $cells = foreach ($column in $TableDiff.Columns) {
                if ($entry.Status -eq 'Changed' -and ($entry.Changed -contains $column)) {
                    $old = ConvertTo-MarkdownCell (Get-DiffRowValue $entry.Row $column) 200
                    $new = ConvertTo-MarkdownCell (Get-DiffRowValue $entry.Other $column) 200
                    "**$old** -> **$new**"
                } else {
                    ConvertTo-MarkdownCell (Get-DiffRowValue $entry.Row $column)
                }
            }
            [void]$Builder.AppendLine("| $(Get-MarkdownStatusIcon $entry.Status) | " + ($cells -join ' | ') + ' |')
        }
        [void]$Builder.AppendLine()
        if ($truncated) {
            [void]$Builder.AppendLine("> Showing the first $MaxRows of $($entries.Count) differing rows.")
            [void]$Builder.AppendLine()
        }
    }

    if ($Collapsed) {
        [void]$Builder.AppendLine('</details>')
        [void]$Builder.AppendLine()
    }
}

function New-MsiMarkdownReport {
    param(
        [Parameter(Mandatory = $true)] $Diff,
        [Parameter(Mandatory = $true)] [string] $Path,
        [int] $MaxRows = 500,
        [switch] $ShowUnchanged
    )

    $sb = New-Object System.Text.StringBuilder
    $s = $Diff.Stats
    $refName = $Diff.Reference.FileName
    $diffName = $Diff.Difference.FileName

    [void]$sb.AppendLine('# MSI package comparison')
    [void]$sb.AppendLine()
    if ($Diff.IsIdentical) {
        [void]$sb.AppendLine('**Verdict: the packages are identical.**')
    } else {
        [void]$sb.AppendLine('**Verdict: the packages differ.**')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Report generated: $($Diff.GeneratedAt)")
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('| | Reference (left) | Difference (right) |')
    [void]$sb.AppendLine('| --- | --- | --- |')
    [void]$sb.AppendLine("| File | $(ConvertTo-MarkdownCell $refName) | $(ConvertTo-MarkdownCell $diffName) |")
    [void]$sb.AppendLine("| Path | $(ConvertTo-MarkdownCell $Diff.Reference.Path) | $(ConvertTo-MarkdownCell $Diff.Difference.Path) |")
    $refSize = [string]::Format([cultureinfo]::InvariantCulture, '{0:N0}', $Diff.Reference.FileSize)
    $diffSize = [string]::Format([cultureinfo]::InvariantCulture, '{0:N0}', $Diff.Difference.FileSize)
    [void]$sb.AppendLine("| Size, bytes | $refSize | $diffSize |")
    [void]$sb.AppendLine("| Modified | $($Diff.Reference.LastWriteTime) | $($Diff.Difference.LastWriteTime) |")
    [void]$sb.AppendLine("| SHA-256 | $($Diff.Reference.FileHash) | $($Diff.Difference.FileHash) |")
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Change summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Metric | Value |')
    [void]$sb.AppendLine('| --- | --- |')
    [void]$sb.AppendLine("| Tables added / removed / changed | $($s.TablesAdded) / $($s.TablesRemoved) / $($s.TablesChanged) |")
    [void]$sb.AppendLine("| Tables unchanged | $($s.TablesIdentical) |")
    [void]$sb.AppendLine("| Rows added / removed / changed | $($s.RowsAdded) / $($s.RowsRemoved) / $($s.RowsChanged) |")
    [void]$sb.AppendLine("| Properties added / removed / changed | $($s.PropertiesAdded) / $($s.PropertiesRemoved) / $($s.PropertiesChanged) |")
    [void]$sb.AppendLine("| Files added / removed / changed | $($s.FilesAdded) / $($s.FilesRemoved) / $($s.FilesChanged) |")
    [void]$sb.AppendLine("| Summary Information fields changed | $($s.SummaryChanged) |")
    [void]$sb.AppendLine()

    if ($Diff.SignificantOnly) {
        [void]$sb.AppendLine('Significant changes only: file size and version (`File.FileSize`, ' +
            '`File.Version`), checksums (`MsiFileHash`), upgrade version bounds ' +
            '(`Upgrade.VersionMin`, `Upgrade.VersionMax`), the `ProductCode` and ' +
            '`ProductVersion` properties and the summary `Comments` field are not taken ' +
            'into account.')
        [void]$sb.AppendLine()
    }
    if ($Diff.IgnoredProperties.Count -or $Diff.IgnoredSummary.Count) {
        [void]$sb.AppendLine('Ignored in this comparison: `' + ((@($Diff.IgnoredSummary) + @($Diff.IgnoredProperties)) -join ', ') + '`')
        [void]$sb.AppendLine()
    }

    Write-MarkdownKeyValueSection -Builder $sb -Title 'Summary Information Stream' `
        -Subtitle 'Package metadata: package code, platform, languages, schema version' `
        -Rows $Diff.SummaryDiff -ReferenceLabel $refName -DifferenceLabel $diffName -ShowUnchanged:$ShowUnchanged

    $propertySubtitle = 'ProductCode, ProductVersion, UpgradeCode and the other installer properties'
    $propertyEmptyMessage = 'No differences.'
    if (-not $Diff.PropertyTableCompared) {
        $propertySubtitle = 'The Property table was excluded by a filter and was not compared.'
        $propertyEmptyMessage = ''
    }
    Write-MarkdownKeyValueSection -Builder $sb -Title 'Property table' `
        -Subtitle $propertySubtitle -EmptyMessage $propertyEmptyMessage `
        -Rows $Diff.PropertyDiff -ReferenceLabel $refName -DifferenceLabel $diffName -ShowUnchanged:$ShowUnchanged

    [void]$sb.AppendLine('## Installed files')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('_File + Component + Directory flattened into target paths. MD5 comes from the MsiFileHash table._')
    [void]$sb.AppendLine()
    if ($Diff.FileViewMissingTables.Count) {
        [void]$sb.AppendLine("> Not compared because of the table filter: ``$($Diff.FileViewMissingTables -join ', ')``. This section is incomplete.")
        [void]$sb.AppendLine()
    }
    Write-MarkdownTableDiff -Builder $sb -TableDiff $Diff.FileDiff -MaxRows $MaxRows

    [void]$sb.AppendLine('## MSI database tables')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Status | Table | + | - | ~ | = | Rows left | Rows right |')
    [void]$sb.AppendLine('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |')
    foreach ($table in $Diff.TableDiffs) {
        [void]$sb.AppendLine("| $(Get-MarkdownStatusIcon $table.Status) | ``$($table.Name)`` | $($table.AddedRows.Count) | $($table.RemovedRows.Count) | $($table.ChangedRows.Count) | $($table.UnchangedCount) | $($table.ReferenceRowCount) | $($table.DifferenceRowCount) |")
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('### Row-level differences')
    [void]$sb.AppendLine()
    $any = $false
    foreach ($table in $Diff.TableDiffs) {
        if ($table.Status -eq 'Identical' -and -not $ShowUnchanged) { continue }
        Write-MarkdownTableDiff -Builder $sb -TableDiff $table -MaxRows $MaxRows -Collapsed
        $any = $true
    }
    if (-not $any) {
        [void]$sb.AppendLine('No table differences.')
        [void]$sb.AppendLine()
    }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    $Path
}
