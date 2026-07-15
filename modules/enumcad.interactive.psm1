<#
.SYNOPSIS
    Interactive console UI module for cad-enum-ps pipeline.
.DESCRIPTION
    Provides interactive menu selection by reading cached/cataloged entries 
    or dynamically walking the local data directory structure.
#>

function Select-CadContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DataFolder = "./Data"
    )
    
    $catalogPath = Join-Path $DataFolder "catalog.json" -replace '\\', '/'
    $choices = @()
    
    # 1. Try reading from catalog.json first if it exists
    if (Test-Path $catalogPath) {
        $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
        if ($catalog.Tree -and $catalog.Tree.Count -gt 0) {
            $choices = $catalog.Tree | Select-Object -Unique State, CountyCode, Year
        }
    }
    
    # 2. Fallback or augment by scanning the local folder tree if catalog is empty/missing
    if ($choices.Count -eq 0 -and (Test-Path $DataFolder)) {
        Write-Host "Catalog not found or empty. Scanning local folder tree in '$DataFolder'..." -ForegroundColor Yellow
        
        $stateDirs = Get-ChildItem -Path $DataFolder -Directory
        foreach ($sDir in $stateDirs) {
            $stateAbr = $sDir.Name
            $countyDirs = Get-ChildItem -Path $sDir.FullName -Directory
            
            foreach ($cDir in $countyDirs) {
                # Expecting format like TX.FB
                if ($cDir.Name -match '^([A-Z]{2})\.([A-Z0-9]+)$') {
                    $cAbr = $Matches[2]
                    # Check for SQLite files matching state.county.year.sqlite
                    $dbFiles = Get-ChildItem -Path $cDir.FullName -Filter "*.sqlite"
                    if ($dbFiles.Count -gt 0) {
                        foreach ($db in $dbFiles) {
                            if ($db.Name -match '^([A-Z]{2})\.([A-Z0-9]+)\.(\d{4})\.sqlite$') {
                                $choices += [PSCustomObject]@{
                                    State      = $Matches[1]
                                    CountyCode = $Matches[2]
                                    Year       = [int]$Matches[3]
                                }
                            }
                        }
                    } else {
                        # Default entry if no database files exist yet under folder
                        $choices += [PSCustomObject]@{
                            State      = $stateAbr
                            CountyCode = $cAbr
                            Year       = 2026
                        }
                    }
                }
            }
        }
    }
    
    if (-not $choices -or $choices.Count -eq 0) {
        Write-Warning "No active contexts found in catalog or local file system."
        return $null
    }
    
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "    Select CAD Context (State/County/Yr) " -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    for ($i = 0; $i -lt $choices.Count; $i++) {
        Write-Host "[$i] State: $($choices[$i].State) | County: $($choices[$i].CountyCode) | Year: $($choices[$i].Year)" -ForegroundColor Green
    }
    Write-Host "-----------------------------------------" -ForegroundColor Cyan
    
    $selection = Read-Host "Enter selection index (or press Enter to abort)"
    if ($selection -match '^\d+$' -and [int]$selection -lt $choices.Count) {
        $chosen = $choices[[int]$selection]
        return [ordered]@{
            State  = $chosen.State
            County = $chosen.CountyCode
            Year   = $chosen.Year
        }
    }
    
    return $null
}

Export-ModuleMember -Function Select-CadContext
