<#
.SYNOPSIS
    Object-oriented SQLite database manager class for EnumCad utilizing PSSQLite.
.DESCRIPTION
    Encapsulates a specific SQLite database file target, handling connection state internally,
    schema initialization, query execution, non-query execution, and transactional batch processing,
    complete with an optional DefaultTable property for quick shortcut routing.
#>

# Ensure PSSQLite module is available in the current environment
if (-not (Get-Module -ListAvailable PSSQLite)) {
    throw "Required module 'PSSQLite' is not installed. Please install it via 'Install-Module PSSQLite'."
}

class cadDB {
    [string]$DataSource
    [string]$DefaultTable

    # Constructor 1: Initialized purely from a file path string
    cadDB([string]$dataSource) {
        $this.DataSource = $dataSource
        $this.DefaultTable = ""
    }

    # Constructor 2: Initialized from a file path string alongside an explicit default table
    cadDB([string]$dataSource, [string]$defaultTable) {
        $this.DataSource = $dataSource
        $this.DefaultTable = $defaultTable
    }

    # Constructor 3: Initialized directly from a district schema object
    cadDB([PSCustomObject]$schema) {
        $this.DataSource = $schema.TargetFile
        $this.DefaultTable = $schema.TableName
    }

    [void] Initialize([PSCustomObject]$schema) {
        $parentDir = Split-Path -Parent $this.DataSource

        if ($parentDir -and -not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }

        Write-Verbose "Initializing database table [$($schema.TableName)] at target: $($this.DataSource)"
        $this.InvokeNonQuery($schema.CreateTableSql)
    }

    [array] InvokeQuery([string]$sql, [hashtable]$parameters = @{}) {
        try {
            if ($parameters.Count -gt 0) {
                return Invoke-SQLiteQuery -DataSource $this.DataSource -Query $sql -SqlParameters $parameters
            } else {
                return Invoke-SQLiteQuery -DataSource $this.DataSource -Query $sql
            }
        }
        catch {
            throw "Failed to execute SQLite query on [$($this.DataSource)]: $_"
        }
    }

    [int] InvokeNonQuery([string]$sql, [hashtable]$parameters = @{}) {
        try {
            if ($parameters.Count -gt 0) {
                return Invoke-SQLiteNonquery -DataSource $this.DataSource -Query $sql -SqlParameters $parameters
            } else {
                return Invoke-SQLiteNonquery -DataSource $this.DataSource -Query $sql
            }
        }
        catch {
            throw "Failed to execute SQLite non-query on [$($this.DataSource)]: $_"
        }
    }

    [int] InvokeBatchTransaction([array]$commands) {
        $successCount = 0

        foreach ($cmd in $commands) {
            try {
                $rowsAffected = $this.InvokeNonQuery($cmd.Sql, $cmd.Parameters)
                
                if ($rowsAffected -eq 0 -and $cmd.WarningHandler) {
                    if ($cmd.WarningHandler -is [scriptblock]) {
                        & $cmd.WarningHandler
                    }
                }
                $successCount++
            }
            catch {
                Write-Warning "Batch command execution failed on [$($this.DataSource)]: $_"
                throw $_
            }
        }

        return $successCount
    }
}

Export-ModuleMember -Class cadDB