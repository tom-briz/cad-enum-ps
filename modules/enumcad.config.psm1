<#
.SYNOPSIS
    Configuration module for CAD Enumeration Pipeline (.REG layer).
.DESCRIPTION
    Manages state manifests, explicit logical tokens (STATE, COUNTY, YEAR), and revised SQLite table maps.
#>

$script:DefaultConfig = [ordered]@{
    THIS_DEF       = $true
    THIS_STATE_ABR = "TX"
    THIS_STATE_EX  = "Texas"
    THIS_COUNTY_ABR= "FB"
    THIS_COUNTY_EX = "Fort Bend"
    THIS_YEAR      = 2026
    DataFolder     = "./Data"
    
    NAMING = [ordered]@{
        STATE_FOLDER  = "{STATE}"
        COUNTY_FOLDER = "{STATE}.{COUNTY}"
        DB_NAME       = "{STATE}.{COUNTY}.{YEAR}.sqlite"
        STRUCT_FILE   = "structure.json"
        CATALOG_FILE  = "catalog.json"
        
        # Internal SQLite Table Names
        TABLES = [ordered]@{
            LOOKUP = "lookup" # Stores lookup fields for the active tax year
            TEMP   = "temp"   # Stores raw page data broken down by sections
            DATA   = "data"   # Stores property data fully decomposed
        }
    }
}

<#
.SYNOPSIS
    Configuration module that reads global CLI flags and manages state persistence.
#>
#Requires -Version 5.1
function Initialize-CadConfig {
    [CmdletBinding()]
    param()

    # 1. Locate config file relative to APP_ROOT
    $configFilePath = Join-Path $global:EnumCadObj.APP_ROOT "config.json"
    $fileConfig = @{}

    if (Test-Path $configFilePath) {
        try {
            $jsonContent = Get-Content -Path $configFilePath -Raw
            $fileConfig = $jsonContent | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Warning "Could not parse existing config.json: $_"
        }
    }

    # 2. Extract CLI flags set by main.ps1
    $cli = $global:EnumCadObj.CLI_PARAMS

    # 3. Resolve District / County Module (CLI -> File -> Master Default)
    $resolvedDist = if ($cli.HasCountyModule -and -not [string]::IsNullOrWhiteSpace($cli.CountyModule)) {
        $cli.CountyModule.Trim()
    } elseif (-not [string]::IsNullOrWhiteSpace($fileConfig.THIS_DIST)) {
        $fileConfig.THIS_DIST
    } else {
        "tx.fb"
    }

    # Parse State and County parts
    if ($resolvedDist.Contains('.')) {
        $modParts       = $resolvedDist.Split('.')
        $resolvedState  = $modParts[0].ToUpper()
        $resolvedCounty = $modParts[1].ToUpper()
    } else {
        $resolvedState  = "TX"
        $resolvedCounty = "FB"
    }

    # 4. Resolve Tax Year (CLI -> File -> Master Default)
    $resolvedYear = if ($cli.HasTaxYear -and $cli.TaxYear -gt 0) {
        [int]$cli.TaxYear
    } elseif ($fileConfig.THIS_YEAR -gt 0) {
        [int]$fileConfig.THIS_YEAR
    } else {
        2026
    }

    # 5. Populate/Update Global Object Properties
    $global:EnumCadObj.THIS_STATE  = $resolvedState
    $global:EnumCadObj.THIS_COUNTY = $resolvedCounty
    $global:EnumCadObj.THIS_DIST   = $resolvedDist.ToLower()
    $global:EnumCadObj.THIS_YEAR   = $resolvedYear
    $global:EnumCadObj.THIS_PREFIX = "$($resolvedState)$($resolvedCounty)CAD"

    if (-not $global:EnumCadObj.ContainsKey('RegistryCache') -or $global:EnumCadObj.RegistryCache.Count -eq 0) {
        $global:EnumCadObj.RegistryCache = if ($fileConfig.RegistryCache) { $fileConfig.RegistryCache } else { @{} }
    }

    # 6. Ensure core directory paths exist
    foreach ($pathKey in @('APP_ROOT', 'MOD_ROOT', 'DIST_ROOT', 'DATA_ROOT')) {
        $targetPath = $global:EnumCadObj[$pathKey]
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
    }

    # 7. Persist updated configuration back to config.json (excluding transient CLI flags)
    try {
        $exportObj = $global:EnumCadObj.psobject.copy() # or create clean hashtable for export
        $saveHash = @{
            THIS_DEF      = $global:EnumCadObj.THIS_DEF
            THIS_STATE    = $global:EnumCadObj.THIS_STATE
            THIS_COUNTY   = $global:EnumCadObj.THIS_COUNTY
            THIS_DIST     = $global:EnumCadObj.THIS_DIST
            THIS_YEAR     = $global:EnumCadObj.THIS_YEAR
            THIS_PREFIX   = $global:EnumCadObj.THIS_PREFIX
            RegistryCache = $global:EnumCadObj.RegistryCache
        }
        $saveHash | ConvertTo-Json -Depth 5 | Set-Content -Path $configFilePath -Force
    }
    catch {
        Write-Warning "Could not persist configuration to config.json: $_"
    }

    Write-Verbose "[$($global:EnumCadObj.THIS_PREFIX)] Configuration state loaded successfully."
    return $global:EnumCadObj
}

Export-ModuleMember -Function Initialize-CadConfig