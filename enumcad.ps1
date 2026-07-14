#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CountyModule,
    
    [Parameter(Mandatory = $false)]
    [int]$TaxYear
)

$script:EnumCadRoot = $PSScriptRoot
if (-not $script:EnumCadRoot) { $script:EnumCadRoot = Get-Location }

# Import Config Module
Import-Module (Join-Path $script:EnumCadRoot "modules/enumcad.config.psm1" -replace '\\', '/') -Force
$Global:EnumCadConfig = Initialize-CadConfig

# Handle Interactive vs Automated Execution
if ($PSBoundParameters.Count -eq 0) {
    # Import and trigger the dedicated interactive module
    Import-Module (Join-Path $script:EnumCadRoot "modules/enumcad.interactive.psm1" -replace '\\', '/') -Force
    
    $picked = Select-CadContext -DataFolder $Global:EnumCadConfig.DataFolder
    if ($picked) {
        $Global:EnumCadConfig.THIS_STATE_ABR  = $picked.State
        $Global:EnumCadConfig.THIS_COUNTY_ABR = $picked.County
    } else {
        Write-Host "Interaction cancelled or no selection made. Using active configuration." -ForegroundColor Yellow
    }
} else {
    if ($TaxYear) { $Global:EnumCadConfig.THIS_YEAR = $TaxYear }
    if ($CountyModule) { $Global:EnumCadConfig.THIS_COUNTY_ABR = $CountyModule }
}

# Resolve execution handles
$targetDataDir  = Resolve-CadPath -Config $Global:EnumCadConfig
$targetDatabase = Resolve-CadPath -Config $Global:EnumCadConfig -AsDatabase

Write-Host "Target Config: $($Global:EnumCadConfig.THIS_STATE_ABR) / $($Global:EnumCadConfig.THIS_COUNTY_ABR) ($($Global:EnumCadConfig.THIS_YEAR))" -ForegroundColor Cyan
