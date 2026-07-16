<#
.SYNOPSIS
    Shared helper utilities, throttling controls, and data storage managers for the EnumCad PowerShell architecture.
.DESCRIPTION
    Provides core runtime helpers including human-like rate-limiting pauses, subdivision catalog
    management, individual property state serialization, and global progress tracking handlers.
#>

<#
.FUNCTION INVENTORY TABLE
------------------------------------------------------------------------------------------------------------------------
Function Name                     Category              Description
------------------------------------------------------------------------------------------------------------------------
Start-HumanPause                | Pacing & Throttling | Introduces triangular or uniform random delays to protect remote endpoints.
Initialize-SubdivisionStorageCatalog | Storage        | Creates individual subdivision folders and manages $code.json catalogs.
Save-SubdivisionCatalog         | Storage             | Serializes and writes subdivision catalog updates to disk.
Save-PropertyStateFile          | Storage             | Writes individual property state JSON files ($QuickRef.json) to disk.
Get-PropertyStateFile           | Storage             | Loads existing individual property state records from disk.
Initialize-SubdivisionTracker   | Tracking            | Initializes the global subdiv.json progress-tracking array.
Update-SubdivisionTrackerStatus | Tracking            | Updates execution status (waiting, pending, complete) in subdiv.json.
------------------------------------------------------------------------------------------------------------------------
#>

<#
.SYNOPSIS
    Pauses execution using a human-like delay with a triangular or uniform distribution.
#>
function Start-HumanPause {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$MinMs = 800,

        [Parameter()]
        [int]$MaxMs = 2000,

        [Parameter()]
        [bool]$Triangular = $true
    )

    $rndNum = if ($Triangular) {
        ((Get-Random -Minimum 0.0 -Maximum 1.0) + (Get-Random -Minimum 0.0 -Maximum 1.0)) / 2
    }
    else {
        (Get-Random -Minimum 0.0 -Maximum 1.0)
    }

    $ms = [Math]::Floor($rndNum * ($MaxMs - $MinMs + 1) + $MinMs)
    Start-Sleep -Milliseconds $ms
}

function Initialize-SubdivisionStorageCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $false)]
        [string]$BaseDataRoot = $global:EnumCadObj.DATA_ROOT
    )

    if ([string]::IsNullOrWhitespace($Code)) {
        throw "Subdivision Code cannot be empty when initializing storage."
    }

    $subDir = Join-Path (Join-Path $BaseDataRoot "subdiv") $Code
    if (-not (Test-Path $subDir)) {
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    }

    $catalogPath = Join-Path $subDir "$Code.json"
    $catalogData = if (Test-Path $catalogPath) {
        Get-Content -Path $catalogPath -Raw | ConvertFrom-Json -AsHashtable
    } else {
        @{
            Code       = $Code
            UpdatedUtc = [DateTime]::UtcNow.ToString("o")
            Properties = @{}
        }
    }

    return [PSCustomObject]@{
        Directory   = $subDir
        CatalogPath = $catalogPath
        Catalog     = $catalogData
    }
}

function Save-SubdivisionCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$StorageContext
    )

    $StorageContext.Catalog.UpdatedUtc = [DateTime]::UtcNow.ToString("o")
    $StorageContext.Catalog | ConvertTo-Json -Depth 10 | Set-Content -Path $StorageContext.CatalogPath -Encoding utf8
}

function Save-PropertyStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubdivisionDirectory,

        [Parameter(Mandatory = $true)]
        [string]$QuickRef,

        [Parameter(Mandatory = $true)]
        [hashtable]$PropertyState
    )

    $propertyFilePath = Join-Path $SubdivisionDirectory "$QuickRef.json"
    $PropertyState | ConvertTo-Json -Depth 5 | Set-Content -Path $propertyFilePath -Encoding utf8
}

function Get-PropertyStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubdivisionDirectory,

        [Parameter(Mandatory = $true)]
        [string]$QuickRef
    )

    $propertyFilePath = Join-Path $SubdivisionDirectory "$QuickRef.json"
    if (Test-Path $propertyFilePath) {
        return Get-Content -Path $propertyFilePath -Raw | ConvertFrom-Json -AsHashtable
    }

    return $null
}

function Initialize-SubdivisionTracker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataRoot
    )

    $subdivJsonPath = Join-Path $DataRoot "subdiv.json"
    if (-not (Test-Path $subdivJsonPath)) {
        @() | ConvertTo-Json -Depth 5 | Set-Content -Path $subdivJsonPath -Encoding utf8
    }

    return $subdivJsonPath
}

function Update-SubdivisionTrackerStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataRoot,

        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [bool]$Complete,

        [int]$PropertyCount
    )

    $subdivJsonPath = Join-Path $DataRoot "subdiv.json"
    if (-not (Test-Path $subdivJsonPath)) { return }

    $trackers = Get-Content -Path $subdivJsonPath -Raw | ConvertFrom-Json
    $target = $trackers | Where-Object { $_.Code -eq $Code }
    if ($target) {
        $target.Complete = $Complete
        if ($PropertyCount -gt 0) {
            $target.Properties = $PropertyCount
        }
    }

    $trackers | ConvertTo-Json -Depth 5 | Set-Content -Path $subdivJsonPath -Encoding utf8
}

Export-ModuleMember -Function `
    Start-HumanPause, `
    Initialize-SubdivisionStorageCatalog, `
    Save-SubdivisionCatalog, `
    Save-PropertyStateFile, `
    Get-PropertyStateFile, `
    Initialize-SubdivisionTracker, `
    Update-SubdivisionTrackerStatus