# Short human-readable summary for the terminal.

$ErrorActionPreference = 'Stop'

function Write-MsiConsoleSummary {
    param([Parameter(Mandatory = $true)] $Diff)

    $s = $Diff.Stats

    Write-Host ''
    Write-Host 'MSI package comparison' -ForegroundColor Cyan
    Write-Host ('  left  : {0}' -f $Diff.Reference.Path)
    Write-Host ('  right : {0}' -f $Diff.Difference.Path)
    if ($Diff.SignificantOnly) {
        Write-Host '  mode  : significant changes only (file size, version and hashes, Upgrade version' -ForegroundColor DarkGray
        Write-Host '          bounds, ProductCode, ProductVersion and summary Comments are ignored)' -ForegroundColor DarkGray
    }
    Write-Host ''

    if ($Diff.IsIdentical) {
        Write-Host '  PACKAGES ARE IDENTICAL' -ForegroundColor Green
    } else {
        Write-Host '  PACKAGES DIFFER' -ForegroundColor Yellow
    }
    Write-Host ''

    Write-Host ('  Summary Information : {0} changed' -f $s.SummaryChanged)
    Write-Host ('  Property            : +{0} / -{1} / ~{2}' -f $s.PropertiesAdded, $s.PropertiesRemoved, $s.PropertiesChanged)
    Write-Host ('  Files               : +{0} / -{1} / ~{2}' -f $s.FilesAdded, $s.FilesRemoved, $s.FilesChanged)
    Write-Host ('  Tables              : +{0} / -{1} / ~{2} (identical: {3})' -f $s.TablesAdded, $s.TablesRemoved, $s.TablesChanged, $s.TablesIdentical)
    Write-Host ('  Rows                : +{0} / -{1} / ~{2}' -f $s.RowsAdded, $s.RowsRemoved, $s.RowsChanged)

    $changed = @($Diff.TableDiffs | Where-Object { $_.Status -ne 'Identical' })
    if ($changed.Count -gt 0) {
        Write-Host ''
        Write-Host '  Changed tables:' -ForegroundColor Cyan
        foreach ($table in $changed) {
            $color = 'Yellow'
            if ($table.Status -eq 'Added') { $color = 'Green' }
            elseif ($table.Status -eq 'Removed') { $color = 'Red' }
            Write-Host ('    {0,-28} +{1,-5} -{2,-5} ~{3,-5}' -f $table.Name, $table.AddedRows.Count, $table.RemovedRows.Count, $table.ChangedRows.Count) -ForegroundColor $color
        }
    }
    Write-Host ''
}
