# Reads an MSI package into plain PowerShell objects so the diff engine never touches the MSI API.

$ErrorActionPreference = 'Stop'

# Summary Information property id -> report name, in report order.
$script:MsiSummaryProperties = @(
    [pscustomobject]@{ Id = 1;  Name = 'Codepage' },
    [pscustomobject]@{ Id = 2;  Name = 'Title' },
    [pscustomobject]@{ Id = 3;  Name = 'Subject' },
    [pscustomobject]@{ Id = 4;  Name = 'Author' },
    [pscustomobject]@{ Id = 5;  Name = 'Keywords' },
    [pscustomobject]@{ Id = 6;  Name = 'Comments' },
    [pscustomobject]@{ Id = 7;  Name = 'Template' },
    [pscustomobject]@{ Id = 8;  Name = 'LastSavedBy' },
    [pscustomobject]@{ Id = 9;  Name = 'PackageCode' },
    [pscustomobject]@{ Id = 11; Name = 'LastPrinted' },
    [pscustomobject]@{ Id = 12; Name = 'CreateTime' },
    [pscustomobject]@{ Id = 13; Name = 'LastSavedTime' },
    [pscustomobject]@{ Id = 14; Name = 'SchemaVersion' },
    [pscustomobject]@{ Id = 15; Name = 'SourceFlags' },
    [pscustomobject]@{ Id = 16; Name = 'CharacterCount' },
    [pscustomobject]@{ Id = 18; Name = 'CreatingApplication' },
    [pscustomobject]@{ Id = 19; Name = 'Security' }
)

function ConvertFrom-MsiSourceFlags {
    param([int] $Value)
    $flags = @()
    if ($Value -band 1) { $flags += 'ShortFileNames' }
    if ($Value -band 2) { $flags += 'Compressed' }
    if ($Value -band 4) { $flags += 'AdminImage' }
    if ($Value -band 8) { $flags += 'LuaPackage' }
    if ($flags.Count -eq 0) { return 'None' }
    $flags -join ', '
}

function ConvertFrom-MsiSecurity {
    param([int] $Value)
    switch ($Value) {
        0 { 'No restriction' }
        2 { 'Read-only recommended' }
        4 { 'Read-only enforced' }
        default { "Unknown ($Value)" }
    }
}

# PowerShell wraps a failed .NET call into MethodInvocationException, whose message
# repeats the call signature. The inner exception carries the message Windows produced.
function Resolve-MsiErrorMessage {
    param([System.Management.Automation.ErrorRecord] $ErrorRecord)
    $exception = $ErrorRecord.Exception
    if ($exception.InnerException) { $exception = $exception.InnerException }
    $exception.Message
}

function Get-MsiSummaryInformation {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $result = [ordered]@{}
    $raw = @{}
    try { $raw = [MsiDiff.PackageReader]::ReadSummary($Path) } catch { return $result }

    foreach ($entry in $script:MsiSummaryProperties) {
        $value = $null
        if ($raw.ContainsKey([int]$entry.Id)) { $value = $raw[[int]$entry.Id] }

        if ($value -is [datetime]) {
            $value = $value.ToString('yyyy-MM-dd HH:mm:ss')
        } elseif ($value -is [string]) {
            $value = $value.Trim()
            if ($value.Length -eq 0) { $value = $null }
        }
        $result[[string]$entry.Name] = $value
    }

    if ($result['Template']) {
        $parts = ([string]$result['Template']).Split(';')
        $result['Template.Platform'] = $parts[0]
        if ($parts.Count -gt 1) { $result['Template.Languages'] = $parts[1] }
    }
    if ($null -ne $result['SourceFlags']) {
        $result['SourceFlags.Decoded'] = ConvertFrom-MsiSourceFlags ([int]$result['SourceFlags'])
    }
    if ($null -ne $result['Security']) {
        $result['Security.Decoded'] = ConvertFrom-MsiSecurity ([int]$result['Security'])
    }

    $result
}

function Read-MsiPackage {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [string[]] $IncludeTable,
        [string[]] $ExcludeTable,
        [switch] $NoStreamHash,
        [scriptblock] $OnProgress
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $fullPath = $item.FullName

    $database = 0
    try {
        try {
            $database = [MsiDiff.PackageReader]::OpenDatabase($fullPath)
        } catch {
            # Keep the message Windows Installer produced. If the file is locked, MSI
            # often reports only ERROR_OPEN_FAILED; a share-restricted open then yields
            # the original sharing-violation text from the file system.
            $reason = Resolve-MsiErrorMessage $_
            try {
                $probe = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $probe.Dispose()
            } catch {
                $io = Resolve-MsiErrorMessage $_
                if ($io) { $reason = "Cannot open '${fullPath}': $io" }
            }
            throw $reason
        }

        $allTables = @([MsiDiff.PackageReader]::GetTableNames($database))

        $selected = $allTables
        if ($IncludeTable -and $IncludeTable.Count -gt 0) {
            $selected = @($selected | Where-Object { $name = $_; ($IncludeTable | Where-Object { $name -like $_ }).Count -gt 0 })
        }
        if ($ExcludeTable -and $ExcludeTable.Count -gt 0) {
            $selected = @($selected | Where-Object { $name = $_; ($ExcludeTable | Where-Object { $name -like $_ }).Count -eq 0 })
        }

        $hashStreams = -not $NoStreamHash
        $tables = [ordered]@{}
        $index = 0
        foreach ($table in $selected) {
            $index++
            if ($OnProgress) { & $OnProgress $item.Name $table $index $selected.Count }

            $native = [MsiDiff.PackageReader]::ReadTable($database, $table, $hashStreams)
            $tables[$table] = [pscustomobject]@{
                Name        = $native.Name
                Columns     = $native.Columns
                ColumnKinds = $native.ColumnKinds
                ColumnTypes = $native.ColumnTypes
                PrimaryKeys = $native.PrimaryKeys
                Rows        = $native.Rows
                Error       = $native.Error
            }
        }

        [pscustomobject]@{
            Path          = $fullPath
            FileName      = $item.Name
            FileSize      = $item.Length
            LastWriteTime = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            FileHash      = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            Summary       = (Get-MsiSummaryInformation -Path $fullPath)
            AllTableNames = $allTables
            Tables        = $tables
        }
    } finally {
        if ($database -ne 0) { [MsiDiff.PackageReader]::CloseDatabase($database) }
    }
}
