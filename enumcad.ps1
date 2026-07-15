#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CountyModule,
    
    [Parameter(Mandatory = $false)]
    [int]$TaxYear
)

# Set Error Action Preference for safety
$ErrorActionPreference = 'Stop'

# 1. Load Core Engine and Global Dependencies
$script:EnumCadRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Parse $CountyModule if provided (e.g., "tx.fb" -> State: "TX", County: "FB")
if (-not [string]::IsNullOrWhiteSpace($CountyModule) -and $CountyModule.Contains('.')) {
    $modParts       = $CountyModule.Split('.')
    $ResolvedState  = $modParts[0]
    $ResolvedCounty = $modParts[1]
    $ResolvedDist   = $CountyModule.Trim()
} else {
    $ResolvedState  = "TX"
    $ResolvedCounty = "FB"
    $ResolvedDist   = if (-not [string]::IsNullOrWhiteSpace($CountyModule)) { $CountyModule.Trim() } else { "tx.fb" }
}

$ResolvedYear = if ($PSBoundParameters.ContainsKey('TaxYear')) { [int]$TaxYear } else { 2026 }

$global:EnumCadObj = @{
    THIS_DEF       = $true
    THIS_STATE     = $ResolvedState.ToUpper()
    THIS_STATE_EX  = "Texas"
    THIS_COUNTY    = $ResolvedCounty.ToUpper()
    THIS_COUNTY_EX = "Fort Bend"
    THIS_DIST      = $ResolvedDist.ToLower()
    THIS_YEAR      = $ResolvedYear
    THIS_PREFIX    = "$($ResolvedState)$($ResolvedCounty)CAD".ToUpper()
    APP_ROOT       = $script:EnumCadRoot
    MOD_ROOT       = Join-Path $script:EnumCadRoot "modules"
    DIST_ROOT      = Join-Path $script:EnumCadRoot "districts"
    DATA_ROOT      = Join-Path $script:EnumCadRoot "data"
    RegistryCache  = @{}
}

# Flag CLI parameters explicitly for the config module to consume
$global:EnumCadObj.CLI_PARAMS = @{
    HasCountyModule = $PSBoundParameters.ContainsKey('CountyModule')
    CountyModule    = $CountyModule
    HasTaxYear      = $PSBoundParameters.ContainsKey('TaxYear')
    TaxYear         = $TaxYear
}

Write-Host "[$($global:EnumCadObj.THIS_PREFIX)] Initializing framework at: $($script:EnumCadRoot)" -ForegroundColor Cyan

# 2. Load Core Dependencies
try {
    Write-Host "Loading core modules..." -ForegroundColor DarkCyan
    Import-Module FetchPS -Force
    Import-Module (Join-Path $global:EnumCadObj.MOD_ROOT "enumcad.config.psm1") -Force
    Import-Module (Join-Path $global:EnumCadObj.MOD_ROOT "enumcad.pssqlite.psm1") -Force
}
catch {
    Write-Error "Failed to load essential core modules: $_"
    exit 1
}

# 3. Load Configuration
try {
    Write-Host "Initializing configuration..." -ForegroundColor DarkCyan
    $Global:EnumCadConfig = Initialize-CadConfig
}
catch {
    Write-Error "Failed to initialize configuration: $_"
    exit 1
}

# 4. Resolve Target District Module (Parameter vs Interactive Menu)
if ($PSBoundParameters.ContainsKey('CountyModule') -and -not [string]::IsNullOrWhiteSpace($CountyModule)) {
    $selectedDistrict = $CountyModule.Trim()
    Write-Host "Using district provided via parameter: $selectedDistrict" -ForegroundColor Yellow
} else {
    # Falls back to interactive prompt if not supplied
    $selectedDistrict = Show-DistrictMenu # Expected format e.g., "tx.fb"
}

# 5. Dynamically Load the Selected District Module on Demand
$districtModulePath = Join-Path $global:EnumCadObj.DIST_ROOT "$selectedDistrict/$selectedDistrict.mod.psm1"
if (-not (Test-Path $districtModulePath)) {
    throw "District module for [$selectedDistrict] could not be found at path: $districtModulePath"
}

Import-Module $districtModulePath -Force
Write-Host "Successfully loaded district profile: $selectedDistrict" -ForegroundColor Green

# 6. Now that the district module is active, grab its schemas and spin up cadDB
try {
    $lookupSchema = Get-DistrictSchema -TableName "lookup"
    $mainDb = [cadDB]::new($lookupSchema)
    $mainDb.Initialize($lookupSchema)

    # Resolve execution paths and handles
    $targetDataDir  = Resolve-CadPath -Config $Global:EnumCadConfig
    $targetDatabase = Resolve-CadPath -Config $Global:EnumCadConfig -AsDatabase

    Write-Host "Target Config: $($Global:EnumCadConfig.THIS_STATE_ABR) / $($Global:EnumCadConfig.THIS_COUNTY_ABR) ($($Global:EnumCadConfig.THIS_YEAR))" -ForegroundColor Cyan
    Write-Host "Database target resolved: $targetDatabase" -ForegroundColor DarkGray
}
catch {
    Write-Error "Error during database initialization or path resolution: $_"
    exit 1
}
