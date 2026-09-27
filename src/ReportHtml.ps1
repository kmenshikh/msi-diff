# Renders a diff result as a single self-contained HTML file.

$ErrorActionPreference = 'Stop'

function ConvertTo-HtmlEncoded {
    param($Text)
    if ($null -eq $Text) { return '' }
    ([string]$Text).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function ConvertTo-HtmlAnchor {
    param([string] $Name)
    'tbl-' + ([regex]::Replace($Name, '[^A-Za-z0-9_-]', '_'))
}

function Get-DiffRowValue {
    param([hashtable] $Row, [string] $Column)
    if ($null -eq $Row -or -not $Row.ContainsKey($Column)) { return '' }
    ConvertTo-MsiDisplayValue $Row[$Column]
}

function Get-DiffStatusClass {
    param([string] $Status)
    switch ($Status) {
        'Added'    { 'add' }
        'Removed'  { 'del' }
        'Changed'  { 'chg' }
        default    { 'same' }
    }
}

function Get-DiffStatusLabel {
    param([string] $Status)
    switch ($Status) {
        'Added'    { 'added' }
        'Removed'  { 'removed' }
        'Changed'  { 'changed' }
        default    { 'unchanged' }
    }
}

function Write-HtmlKeyValueSection {
    param(
        [System.Text.StringBuilder] $Builder,
        [string] $Id,
        [string] $Title,
        [string] $Subtitle,
        $Rows,
        [string] $ReferenceLabel,
        [string] $DifferenceLabel,
        [string] $EmptyMessage = 'No data.'
    )

    $changedCount = @($Rows | Where-Object { $_.Status -ne 'Identical' }).Count

    [void]$Builder.AppendLine("<section class=""card"" id=""$Id"">")
    [void]$Builder.AppendLine("<h2>$(ConvertTo-HtmlEncoded $Title) <span class=""count"">$changedCount of $(@($Rows).Count)</span></h2>")
    if ($Subtitle) { [void]$Builder.AppendLine("<p class=""sub"">$(ConvertTo-HtmlEncoded $Subtitle)</p>") }

    if (@($Rows).Count -eq 0) {
        if ($EmptyMessage) { [void]$Builder.AppendLine("<p class=""empty"">$(ConvertTo-HtmlEncoded $EmptyMessage)</p>") }
        [void]$Builder.AppendLine('</section>')
        return
    }

    [void]$Builder.AppendLine('<div class="tablewrap"><table class="grid">')
    [void]$Builder.AppendLine("<thead><tr><th class=""col-st"">Status</th><th>Name</th><th>$(ConvertTo-HtmlEncoded $ReferenceLabel)</th><th>$(ConvertTo-HtmlEncoded $DifferenceLabel)</th></tr></thead><tbody>")
    foreach ($row in $Rows) {
        $cls = Get-DiffStatusClass $row.Status
        [void]$Builder.AppendLine("<tr class=""r-$cls"" data-diff=""$(if ($row.Status -eq 'Identical') { '0' } else { '1' })"">" +
            "<td class=""col-st""><span class=""badge b-$cls"">$(Get-DiffStatusLabel $row.Status)</span></td>" +
            "<td class=""k"">$(ConvertTo-HtmlEncoded $row.Name)</td>" +
            "<td>$(ConvertTo-HtmlEncoded $row.Reference)</td>" +
            "<td>$(ConvertTo-HtmlEncoded $row.Difference)</td></tr>")
    }
    [void]$Builder.AppendLine('</tbody></table></div></section>')
}

function Write-HtmlTableDiff {
    param(
        [System.Text.StringBuilder] $Builder,
        $TableDiff,
        [int] $MaxRows,
        [switch] $ShowUnchanged,
        [switch] $StartOpen
    )

    $anchor = ConvertTo-HtmlAnchor $TableDiff.Name
    $cls = Get-DiffStatusClass $TableDiff.Status
    $open = ''
    if ($StartOpen -and $TableDiff.Status -ne 'Identical') { $open = ' open' }

    [void]$Builder.AppendLine("<details class=""tbl t-$cls"" id=""$anchor"" data-diff=""$(if ($TableDiff.Status -eq 'Identical') { '0' } else { '1' })""$open>")
    [void]$Builder.AppendLine('<summary>')
    [void]$Builder.AppendLine("<span class=""tname"">$(ConvertTo-HtmlEncoded $TableDiff.Name)</span>")
    [void]$Builder.AppendLine("<span class=""badge b-$cls"">$(Get-DiffStatusLabel $TableDiff.Status)</span>")
    if ($TableDiff.AddedRows.Count)   { [void]$Builder.AppendLine("<span class=""pill p-add"">+$($TableDiff.AddedRows.Count)</span>") }
    if ($TableDiff.RemovedRows.Count) { [void]$Builder.AppendLine("<span class=""pill p-del"">&minus;$($TableDiff.RemovedRows.Count)</span>") }
    if ($TableDiff.ChangedRows.Count) { [void]$Builder.AppendLine("<span class=""pill p-chg"">~$($TableDiff.ChangedRows.Count)</span>") }
    [void]$Builder.AppendLine("<span class=""tmeta"">rows: $($TableDiff.ReferenceRowCount) &rarr; $($TableDiff.DifferenceRowCount)</span>")
    [void]$Builder.AppendLine('</summary>')

    if ($TableDiff.KeyColumns.Count) {
        [void]$Builder.AppendLine("<p class=""sub"">Match key: <code>$(ConvertTo-HtmlEncoded ($TableDiff.KeyColumns -join ', '))</code></p>")
    }
    if ($TableDiff.IgnoredColumns.Count) {
        [void]$Builder.AppendLine("<p class=""sub"">Ignored columns: <code>$(ConvertTo-HtmlEncoded ($TableDiff.IgnoredColumns -join ', '))</code></p>")
    }
    if ($TableDiff.IgnoredRowKeys.Count) {
        [void]$Builder.AppendLine("<p class=""sub"">Ignored rows: <code>$(ConvertTo-HtmlEncoded ($TableDiff.IgnoredRowKeys -join ', '))</code></p>")
    }
    if ($TableDiff.ColumnsOnlyInReference.Count) {
        [void]$Builder.AppendLine("<p class=""warn"">Columns only on the left: <code>$(ConvertTo-HtmlEncoded ($TableDiff.ColumnsOnlyInReference -join ', '))</code></p>")
    }
    if ($TableDiff.ColumnsOnlyInDifference.Count) {
        [void]$Builder.AppendLine("<p class=""warn"">Columns only on the right: <code>$(ConvertTo-HtmlEncoded ($TableDiff.ColumnsOnlyInDifference -join ', '))</code></p>")
    }

    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($row in $TableDiff.RemovedRows) { $entries.Add([pscustomobject]@{ Status = 'Removed'; Row = $row; Other = $null; Changed = @() }) }
    foreach ($row in $TableDiff.AddedRows)   { $entries.Add([pscustomobject]@{ Status = 'Added'; Row = $row; Other = $null; Changed = @() }) }
    foreach ($row in $TableDiff.ChangedRows) { $entries.Add([pscustomobject]@{ Status = 'Changed'; Row = $row.Reference; Other = $row.Difference; Changed = $row.ChangedColumns }) }

    if ($entries.Count -eq 0) {
        [void]$Builder.AppendLine('<p class="empty">No differences.</p></details>')
        return
    }

    $truncated = $false
    if ($MaxRows -gt 0 -and $entries.Count -gt $MaxRows) {
        $shown = $entries.GetRange(0, $MaxRows)
        $truncated = $true
    } else {
        $shown = $entries
    }

    [void]$Builder.AppendLine('<div class="tablewrap"><table class="grid"><thead><tr><th class="col-st">Status</th>')
    foreach ($column in $TableDiff.Columns) {
        $keyMark = ''
        if ($TableDiff.KeyColumns -contains $column) { $keyMark = ' class="pk"' }
        [void]$Builder.AppendLine("<th$keyMark>$(ConvertTo-HtmlEncoded $column)</th>")
    }
    [void]$Builder.AppendLine('</tr></thead><tbody>')

    foreach ($entry in $shown) {
        $rowCls = Get-DiffStatusClass $entry.Status
        [void]$Builder.Append("<tr class=""r-$rowCls""><td class=""col-st""><span class=""badge b-$rowCls"">$(Get-DiffStatusLabel $entry.Status)</span></td>")
        foreach ($column in $TableDiff.Columns) {
            if ($entry.Status -eq 'Changed' -and ($entry.Changed -contains $column)) {
                $old = ConvertTo-HtmlEncoded (Get-DiffRowValue $entry.Row $column)
                $new = ConvertTo-HtmlEncoded (Get-DiffRowValue $entry.Other $column)
                [void]$Builder.Append("<td class=""c-chg""><span class=""v-old"">$old</span><span class=""v-arrow"">&rarr;</span><span class=""v-new"">$new</span></td>")
            } else {
                $source = $entry.Row
                if ($entry.Status -eq 'Changed' -and $null -eq $source) { $source = $entry.Other }
                [void]$Builder.Append("<td>$(ConvertTo-HtmlEncoded (Get-DiffRowValue $source $column))</td>")
            }
        }
        [void]$Builder.AppendLine('</tr>')
    }
    [void]$Builder.AppendLine('</tbody></table></div>')

    if ($truncated) {
        [void]$Builder.AppendLine("<p class=""warn"">Showing the first $MaxRows of $($entries.Count) differing rows. Raise -MaxRowsPerTable to see the rest.</p>")
    }
    if ($ShowUnchanged -and $TableDiff.UnchangedCount -gt 0) {
        [void]$Builder.AppendLine("<p class=""sub"">Identical rows: $($TableDiff.UnchangedCount).</p>")
    }
    [void]$Builder.AppendLine('</details>')
}

function New-MsiHtmlReport {
    param(
        [Parameter(Mandatory = $true)] $Diff,
        [Parameter(Mandatory = $true)] [string] $Path,
        [int] $MaxRows = 500,
        [switch] $ShowUnchanged
    )

    $sb = New-Object System.Text.StringBuilder
    $refName = $Diff.Reference.FileName
    $diffName = $Diff.Difference.FileName
    $verdictClass = 'chg'
    $verdictText = 'Packages differ'
    if ($Diff.IsIdentical) {
        $verdictClass = 'same'
        $verdictText = 'Packages are identical'
    }

    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>MSI diff: $(ConvertTo-HtmlEncoded $refName) &rarr; $(ConvertTo-HtmlEncoded $diffName)</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine((Get-MsiReportCss))
    [void]$sb.AppendLine('</style></head><body>')

    # ---- header -------------------------------------------------------
    [void]$sb.AppendLine('<header class="hero">')
    [void]$sb.AppendLine('<h1>MSI package comparison</h1>')
    [void]$sb.AppendLine("<div class=""verdict v-$verdictClass"">$verdictText</div>")
    [void]$sb.AppendLine('<div class="pkgs">')
    foreach ($pair in @(@('Reference (left)', $Diff.Reference), @('Difference (right)', $Diff.Difference))) {
        $label = $pair[0]
        $pkg = $pair[1]
        [void]$sb.AppendLine('<div class="pkg">')
        [void]$sb.AppendLine("<div class=""pkg-label"">$(ConvertTo-HtmlEncoded $label)</div>")
        [void]$sb.AppendLine("<div class=""pkg-name"">$(ConvertTo-HtmlEncoded $pkg.FileName)</div>")
        [void]$sb.AppendLine("<dl><dt>Path</dt><dd>$(ConvertTo-HtmlEncoded $pkg.Path)</dd>")
        [void]$sb.AppendLine("<dt>Size</dt><dd>$([string]::Format([cultureinfo]::InvariantCulture, '{0:N0}', $pkg.FileSize)) bytes</dd>")
        [void]$sb.AppendLine("<dt>Modified</dt><dd>$(ConvertTo-HtmlEncoded $pkg.LastWriteTime)</dd>")
        [void]$sb.AppendLine("<dt>SHA-256</dt><dd class=""mono"">$(ConvertTo-HtmlEncoded $pkg.FileHash)</dd></dl>")
        [void]$sb.AppendLine('</div>')
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine("<p class=""stamp"">Report generated $(ConvertTo-HtmlEncoded $Diff.GeneratedAt)</p>")
    [void]$sb.AppendLine('</header>')

    # ---- toolbar ------------------------------------------------------
    [void]$sb.AppendLine('<div class="toolbar">')
    [void]$sb.AppendLine('<input type="search" id="q" placeholder="Filter report rows...">')
    $onlyDiffChecked = ' checked'
    if ($ShowUnchanged) { $onlyDiffChecked = '' }
    [void]$sb.AppendLine("<label><input type=""checkbox"" id=""onlyDiff""$onlyDiffChecked> differences only</label>")
    [void]$sb.AppendLine('<button type="button" data-act="expand">Expand all</button>')
    [void]$sb.AppendLine('<button type="button" data-act="collapse">Collapse all</button>')
    [void]$sb.AppendLine('<span class="spacer"></span>')
    [void]$sb.AppendLine('<a href="#summary">Summary</a><a href="#properties">Property</a><a href="#files">Files</a><a href="#tables">Tables</a>')
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('<main>')

    # ---- stat cards ---------------------------------------------------
    $s = $Diff.Stats
    [void]$sb.AppendLine('<section class="cards">')
    foreach ($card in @(
        @('Tables changed', $s.TablesChanged, 'chg'),
        @('Tables added', $s.TablesAdded, 'add'),
        @('Tables removed', $s.TablesRemoved, 'del'),
        @('Rows added', $s.RowsAdded, 'add'),
        @('Rows removed', $s.RowsRemoved, 'del'),
        @('Rows changed', $s.RowsChanged, 'chg'),
        @('Files +/-/~', "$($s.FilesAdded)/$($s.FilesRemoved)/$($s.FilesChanged)", 'chg'),
        @('Properties +/-/~', "$($s.PropertiesAdded)/$($s.PropertiesRemoved)/$($s.PropertiesChanged)", 'chg')
    )) {
        [void]$sb.AppendLine("<div class=""stat s-$($card[2])""><div class=""stat-v"">$($card[1])</div><div class=""stat-l"">$($card[0])</div></div>")
    }
    [void]$sb.AppendLine('</section>')

    if ($Diff.IgnoredProperties.Count -or $Diff.IgnoredSummary.Count -or $Diff.SignificantOnly) {
        [void]$sb.AppendLine('<section class="card"><h2>Ignored in this comparison</h2>')
        if ($Diff.SignificantOnly) {
            [void]$sb.AppendLine('<p class="sub">Significant changes only: file size and version ' +
                '(<code>File.FileSize</code>, <code>File.Version</code>), checksums (<code>MsiFileHash</code>), ' +
                'upgrade version bounds (<code>Upgrade.VersionMin</code>, <code>Upgrade.VersionMax</code>), ' +
                'the <code>ProductCode</code> and <code>ProductVersion</code> properties and the summary ' +
                '<code>Comments</code> field are not taken into account.</p>')
        }
        if ($Diff.IgnoredProperties.Count -or $Diff.IgnoredSummary.Count) {
            [void]$sb.AppendLine('<p class="sub">' +
                (ConvertTo-HtmlEncoded ((@($Diff.IgnoredSummary) + @($Diff.IgnoredProperties)) -join ', ')) + '</p>')
        }
        [void]$sb.AppendLine('</section>')
    }

    Write-HtmlKeyValueSection -Builder $sb -Id 'summary' -Title 'Summary Information Stream' `
        -Subtitle 'Package metadata: package code, platform, languages, schema version' `
        -Rows $Diff.SummaryDiff -ReferenceLabel $refName -DifferenceLabel $diffName

    $propertySubtitle = 'ProductCode, ProductVersion, UpgradeCode and the other installer properties'
    $propertyEmptyMessage = 'No data.'
    if (-not $Diff.PropertyTableCompared) {
        $propertySubtitle = 'The Property table was excluded by a filter and was not compared.'
        $propertyEmptyMessage = ''
    }
    Write-HtmlKeyValueSection -Builder $sb -Id 'properties' -Title 'Property table' `
        -Subtitle $propertySubtitle -EmptyMessage $propertyEmptyMessage `
        -Rows $Diff.PropertyDiff -ReferenceLabel $refName -DifferenceLabel $diffName

    # ---- files --------------------------------------------------------
    [void]$sb.AppendLine('<section class="card" id="files">')
    [void]$sb.AppendLine("<h2>Installed files <span class=""count"">+$($s.FilesAdded) / &minus;$($s.FilesRemoved) / ~$($s.FilesChanged)</span></h2>")
    [void]$sb.AppendLine('<p class="sub">File + Component + Directory flattened into target paths. MD5 comes from the MsiFileHash table.</p>')
    if ($Diff.FileViewMissingTables.Count) {
        [void]$sb.AppendLine("<p class=""warn"">Not compared because of the table filter: <code>$(ConvertTo-HtmlEncoded ($Diff.FileViewMissingTables -join ', '))</code>. This section is incomplete.</p>")
    }
    Write-HtmlTableDiff -Builder $sb -TableDiff $Diff.FileDiff -MaxRows $MaxRows -ShowUnchanged:$ShowUnchanged -StartOpen
    [void]$sb.AppendLine('</section>')

    # ---- tables -------------------------------------------------------
    [void]$sb.AppendLine('<section class="card" id="tables">')
    [void]$sb.AppendLine('<h2>MSI database tables</h2>')
    [void]$sb.AppendLine('<p class="sub">Row-by-row comparison using the primary key of each table.</p>')
    [void]$sb.AppendLine('<div class="tablewrap"><table class="grid overview"><thead><tr><th class="col-st">Status</th><th>Table</th>' +
        '<th class="num">+</th><th class="num">&minus;</th><th class="num">~</th><th class="num">=</th>' +
        '<th class="num">Rows left</th><th class="num">Rows right</th></tr></thead><tbody>')
    foreach ($table in $Diff.TableDiffs) {
        $cls = Get-DiffStatusClass $table.Status
        $anchor = ConvertTo-HtmlAnchor $table.Name
        [void]$sb.AppendLine("<tr class=""r-$cls"" data-diff=""$(if ($table.Status -eq 'Identical') { '0' } else { '1' })"">" +
            "<td class=""col-st""><span class=""badge b-$cls"">$(Get-DiffStatusLabel $table.Status)</span></td>" +
            "<td><a href=""#$anchor"">$(ConvertTo-HtmlEncoded $table.Name)</a></td>" +
            "<td class=""num"">$($table.AddedRows.Count)</td><td class=""num"">$($table.RemovedRows.Count)</td>" +
            "<td class=""num"">$($table.ChangedRows.Count)</td><td class=""num"">$($table.UnchangedCount)</td>" +
            "<td class=""num"">$($table.ReferenceRowCount)</td><td class=""num"">$($table.DifferenceRowCount)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div>')

    foreach ($table in $Diff.TableDiffs) {
        if ($table.Status -eq 'Identical' -and -not $ShowUnchanged) { continue }
        Write-HtmlTableDiff -Builder $sb -TableDiff $table -MaxRows $MaxRows -ShowUnchanged:$ShowUnchanged
    }
    [void]$sb.AppendLine('</section>')

    [void]$sb.AppendLine('</main>')
    [void]$sb.AppendLine('<script>')
    [void]$sb.AppendLine((Get-MsiReportScript))
    [void]$sb.AppendLine('</script></body></html>')

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    $Path
}

function Get-MsiReportCss {
@'
:root{
  --bg:#f6f7f9; --fg:#1f2328; --muted:#636c76; --card:#ffffff; --line:#d8dee4;
  --add:#1a7f37; --add-bg:#e8f5ec; --del:#cf222e; --del-bg:#ffeceb; --chg:#9a6700; --chg-bg:#fff6d9;
  --accent:#0969da;
}
@media (prefers-color-scheme:dark){
  :root{ --bg:#0d1117; --fg:#e6edf3; --muted:#9198a1; --card:#161b22; --line:#30363d;
    --add:#3fb950; --add-bg:#12261a; --del:#f85149; --del-bg:#2d1213; --chg:#d29922; --chg-bg:#2b2311;
    --accent:#4493f8; }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
code,.mono{font-family:ui-monospace,"Cascadia Mono",Consolas,"Liberation Mono",monospace;font-size:12.5px}
.hero{padding:28px 32px 20px;background:var(--card);border-bottom:1px solid var(--line)}
.hero h1{margin:0 0 12px;font-size:22px;font-weight:600}
.verdict{display:inline-block;padding:6px 14px;border-radius:999px;font-weight:600;font-size:13px;margin-bottom:18px}
.v-chg{background:var(--chg-bg);color:var(--chg);border:1px solid var(--chg)}
.v-same{background:var(--add-bg);color:var(--add);border:1px solid var(--add)}
.pkgs{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px}
.pkg{border:1px solid var(--line);border-radius:8px;padding:14px 16px;background:var(--bg)}
.pkg-label{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}
.pkg-name{font-size:16px;font-weight:600;margin:2px 0 10px;word-break:break-all}
.pkg dl{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;margin:0;font-size:12.5px}
.pkg dt{color:var(--muted)}
.pkg dd{margin:0;word-break:break-all}
.stamp{color:var(--muted);font-size:12px;margin:14px 0 0}
.toolbar{position:sticky;top:0;z-index:20;display:flex;align-items:center;gap:10px;flex-wrap:wrap;
  padding:10px 32px;background:var(--card);border-bottom:1px solid var(--line)}
.toolbar input[type=search]{flex:0 1 320px;padding:6px 10px;border:1px solid var(--line);border-radius:6px;
  background:var(--bg);color:var(--fg)}
.toolbar button{padding:6px 12px;border:1px solid var(--line);border-radius:6px;background:var(--bg);
  color:var(--fg);cursor:pointer}
.toolbar button:hover{border-color:var(--accent);color:var(--accent)}
.toolbar label{font-size:13px;color:var(--muted);cursor:pointer;user-select:none}
.toolbar .spacer{flex:1}
main{padding:24px 32px 64px;max-width:1800px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:24px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:14px 16px}
.stat-v{font-size:24px;font-weight:600;line-height:1.1}
.stat-l{font-size:12px;color:var(--muted);margin-top:4px}
.s-add .stat-v{color:var(--add)} .s-del .stat-v{color:var(--del)} .s-chg .stat-v{color:var(--chg)}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:18px 20px;margin-bottom:20px}
.card>h2{margin:0 0 4px;font-size:17px;font-weight:600;display:flex;align-items:baseline;gap:10px}
.count{font-size:12px;font-weight:400;color:var(--muted)}
.sub{color:var(--muted);font-size:12.5px;margin:0 0 12px}
.warn{color:var(--chg);font-size:12.5px;margin:6px 0}
.empty{color:var(--muted);font-size:13px;margin:6px 0}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:6px}
table.grid{border-collapse:collapse;width:100%;font-size:12.5px}
table.grid th{position:sticky;top:0;background:var(--card);text-align:left;font-weight:600;
  padding:7px 10px;border-bottom:1px solid var(--line);white-space:nowrap;z-index:1}
table.grid th.pk::after{content:" \01F511";font-size:10px}
table.grid td{padding:6px 10px;border-bottom:1px solid var(--line);vertical-align:top;
  max-width:560px;overflow-wrap:break-word;word-break:break-word}
table.grid tbody tr:last-child td{border-bottom:none}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
td.k{font-weight:600;white-space:nowrap}
.col-st{width:1%;white-space:nowrap}
.r-add{background:var(--add-bg)} .r-del{background:var(--del-bg)} .r-chg{background:var(--chg-bg)}
.badge{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:600;white-space:nowrap}
.b-add{background:var(--add-bg);color:var(--add);border:1px solid var(--add)}
.b-del{background:var(--del-bg);color:var(--del);border:1px solid var(--del)}
.b-chg{background:var(--chg-bg);color:var(--chg);border:1px solid var(--chg)}
.b-same{background:transparent;color:var(--muted);border:1px solid var(--line)}
.c-chg .v-old{color:var(--del);text-decoration:line-through;opacity:.85}
.c-chg .v-arrow{color:var(--muted);margin:0 6px}
.c-chg .v-new{color:var(--add);font-weight:600}
details.tbl{border:1px solid var(--line);border-radius:8px;margin:10px 0;background:var(--card)}
details.tbl>summary{cursor:pointer;padding:10px 14px;display:flex;align-items:center;gap:10px;flex-wrap:wrap;
  list-style:none;user-select:none}
details.tbl>summary::-webkit-details-marker{display:none}
details.tbl>summary::before{content:"\25B8";color:var(--muted);transition:transform .12s}
details.tbl[open]>summary::before{transform:rotate(90deg)}
details.tbl>summary:hover{background:var(--bg)}
details.tbl .tname{font-weight:600;font-size:14px}
details.tbl .tmeta{color:var(--muted);font-size:12px;margin-left:auto}
details.tbl>*:not(summary){margin-left:14px;margin-right:14px}
details.tbl>.tablewrap{margin-bottom:14px}
.pill{font-size:11.5px;font-weight:600;padding:1px 7px;border-radius:5px;font-variant-numeric:tabular-nums}
.p-add{background:var(--add-bg);color:var(--add)}
.p-del{background:var(--del-bg);color:var(--del)}
.p-chg{background:var(--chg-bg);color:var(--chg)}
.hidden{display:none !important}
'@
}

function Get-MsiReportScript {
@'
(function () {
  var q = document.getElementById('q');
  var onlyDiff = document.getElementById('onlyDiff');

  function apply() {
    var needle = q.value.trim().toLowerCase();
    var diffOnly = onlyDiff.checked;

    document.querySelectorAll('tbody tr').forEach(function (tr) {
      var hideByDiff = diffOnly && tr.dataset.diff === '0';
      var hideByText = needle && tr.textContent.toLowerCase().indexOf(needle) === -1;
      tr.classList.toggle('hidden', hideByDiff || hideByText);
    });

    document.querySelectorAll('details.tbl').forEach(function (d) {
      var hideByDiff = diffOnly && d.dataset.diff === '0';
      var hideByText = false;
      if (needle) {
        var visibleRows = d.querySelectorAll('tbody tr:not(.hidden)').length;
        hideByText = visibleRows === 0 && d.querySelector('.tname').textContent.toLowerCase().indexOf(needle) === -1;
      }
      d.classList.toggle('hidden', hideByDiff || hideByText);
    });
  }

  q.addEventListener('input', apply);
  onlyDiff.addEventListener('change', apply);

  document.querySelectorAll('.toolbar button').forEach(function (b) {
    b.addEventListener('click', function () {
      var open = b.dataset.act === 'expand';
      document.querySelectorAll('details.tbl').forEach(function (d) { d.open = open; });
    });
  });

  document.querySelectorAll('a[href^="#tbl-"]').forEach(function (a) {
    a.addEventListener('click', function () {
      var target = document.getElementById(a.getAttribute('href').slice(1));
      if (target) { target.open = true; target.classList.remove('hidden'); }
    });
  });

  apply();
})();
'@
}
