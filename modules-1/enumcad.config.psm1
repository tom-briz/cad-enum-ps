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

function Initialize-CadConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = "./Config/config.json"
    )
    
    $config = $script:DefaultConfig
    if (Test-Path $ConfigPath) {
        $loaded = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in $loaded.Keys) { $config[$key] = $loaded[$key] }
    }
    
    $stateDir = $config.NAMING.STATE_FOLDER -replace '{STATE}', $config.THIS_STATE_ABR
    $countyDir = $config.NAMING.COUNTY_FOLDER -replace '{STATE}', $config.THIS_STATE_ABR -replace '{COUNTY}', $config.THIS_COUNTY_ABR
    $dataStructPath = Join-Path (Join-Path $config.DataFolder $stateDir) "$countyDir/$($config.NAMING.STRUCT_FILE)"
    $dataStructPath = $dataStructPath -replace '\\', '/'
    
    if (Test-Path $dataStructPath) {
        $localStruct = Get-Content $dataStructPath -Raw | ConvertFrom-Json -AsHashtable
        foreach ($key in $localStruct.Keys) { $config['NAMING'][$key] = $localStruct[$key] }
    }
    
    return [PSCustomObject]$config
}

function Resolve-CadPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Config = (Initialize-CadConfig),
        
        [Parameter(Mandatory = $false)]
        [int]$TaxYear = $Config.THIS_YEAR,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsDatabase
    )
    
    $stateDir = $Config.NAMING.STATE_FOLDER -replace '{STATE}', $Config.THIS_STATE_ABR
    
    $countyFolderPattern = $Config.NAMING.COUNTY_FOLDER -replace '{STATE}', $Config.THIS_STATE_ABR
    $countyDir = $countyFolderPattern -replace '{COUNTY}', $Config.THIS_COUNTY_ABR
    
    $baseDir = Join-Path (Join-Path $Config.DataFolder $stateDir) $countyDir
    $baseDir = $baseDir -replace '\\', '/'
    
    if (-not (Test-Path $baseDir)) {
        New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
    }
    
    if ($AsDatabase) {
        $dbNamePattern = $Config.NAMING.DB_NAME -replace '{STATE}', $Config.THIS_STATE_ABR
        $dbNamePattern = $dbNamePattern -replace '{COUNTY}', $Config.THIS_COUNTY_ABR
        $dbFileName = $dbNamePattern -replace '{YEAR}', $TaxYear
        return (Join-Path $baseDir $dbFileName) -replace '\\', '/'
    }
    
    return $baseDir
}

Export-ModuleMember -Function Initialize-CadConfig, Resolve-CadPath
