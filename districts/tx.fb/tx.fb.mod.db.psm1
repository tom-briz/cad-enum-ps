<#
.SYNOPSIS
    Deterministic schema definitions, lookup endpoints, and SQL command builders for Fort Bend County.
.DESCRIPTION
    Exposes standardized table schemas, lookup endpoint metadata structures, and functions
    for building database commands, querying lookup registries, and resolving remote lookup payloads.
#>

# 1. Module-Level Constants & Metadata (Strict Global Configuration Assertions)
if (-not $global:config -or -not $global:config.THIS_YEAR) {
    throw "Strict Configuration Error: `$global:config.THIS_YEAR must be defined prior to loading the district module."
}

$script:CadPrefix = "tx.fb"
$script:TaxYear = $global:config.THIS_YEAR

# 2. Module-Level Lookup Registry Objects
$script:LookupRegistry = @(
    [PSCustomObject]@{
        Term        = "abstracts"
        Name        = "Abstract List"
        Description = "Query endpoint for unmapped acreage and abstract-level property records."
        Path        = "/Search/AbstractList"
    },
    [PSCustomObject]@{
        Term        = "subdivisions"
        Name        = "Subdivision List"
        Description = "Query endpoint for platted subdivision and neighborhood lots."
        Path        = "/Search/SubdivisionList"
    },
    [PSCustomObject]@{
        Term        = "condos"
        Name        = "Condo List"
        Description = "Query endpoint for condominium complexes and unit breakdowns."
        Path        = "/Search/CondoList"
    },
    [PSCustomObject]@{
        Term        = "mobileHomes"
        Name        = "Mobile Home List"
        Description = "Query endpoint for personal property mobile and manufactured homes."
        Path        = "/Search/MobileHomeList"
    }
)

# 3. Database Schema Definitions (Bound to physical file targets)
$script:DistrictSchemas = @{
    "lookup" = [PSCustomObject]@{
        TableName      = "lookup"
        TargetFile     = "$($script:CadPrefix).$($script:TaxYear).sqlite"
        IsTemporary    = $false
        CreateTableSql = @"
CREATE TABLE IF NOT EXISTS lookup (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tax_year INTEGER NOT NULL,
    lookup_type TEXT NOT NULL,
    text TEXT,
    code TEXT,
    family TEXT,
    section TEXT,
    name TEXT,
    prop_count INTEGER DEFAULT 0,
    CONSTRAINT UQ_lookup_key UNIQUE (tax_year, lookup_type, text)
);
"@
        Columns        = @("id", "tax_year", "lookup_type", "text", "code", "family", "section", "name", "prop_count")
    }

    "prop-list" = [PSCustomObject]@{
        TableName      = "prop_list"
        TargetFile     = "$($script:CadPrefix).$($script:TaxYear).sqlite"
        IsTemporary    = $false
        CreateTableSql = @"
CREATE TABLE IF NOT EXISTS prop_list (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tax_year INTEGER NOT NULL,
    subdivision TEXT NOT NULL,
    property_id TEXT NOT NULL,
    appraised_value REAL,
    property_type TEXT,
    property_type_code TEXT,
    address TEXT,
    street_number TEXT,
    street_name TEXT,
    neighborhood_code TEXT,
    legal_description TEXT,
    owner_percent INTEGER,
    owner_primary INTEGER,
    owner_id TEXT,
    owner_name TEXT,
    lookup_id INTEGER,
    prop_detail_id INTEGER,
    CONSTRAINT FK_lookup_subdivision FOREIGN KEY (lookup_id) 
        REFERENCES lookup(id) ON DELETE SET NULL,
    CONSTRAINT FK_prop_detail FOREIGN KEY (prop_detail_id) 
        REFERENCES prop_detail(id) ON DELETE SET NULL,
    CONSTRAINT UQ_prop_list_composite UNIQUE (tax_year, subdivision, property_id)
);
"@
        Columns        = @(
            "id", "tax_year", "subdivision", "property_id", "appraised_value", 
            "property_type", "property_type_code", "address", "street_number", 
            "street_name", "neighborhood_code", "legal_description", 
            "owner_percent", "owner_primary", "owner_id", "owner_name", 
            "lookup_id", "prop_detail_id"
        )
    }

    "prop-detail" = [PSCustomObject]@{
        TableName      = "prop_detail"
        TargetFile     = "$($script:CadPrefix).$($script:TaxYear).sqlite"
        IsTemporary    = $false
        CreateTableSql = @"
CREATE TABLE IF NOT EXISTS prop_detail (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tax_year INTEGER NOT NULL,
    property_id TEXT NOT NULL,
    raw_json TEXT,
    normalized_data TEXT,
    prop_list_id INTEGER,
    CONSTRAINT FK_prop_list FOREIGN KEY (prop_list_id) 
        REFERENCES prop_list(id) ON DELETE CASCADE,
    CONSTRAINT UQ_prop_detail_key UNIQUE (tax_year, property_id)
);
"@
        Columns        = @("id", "tax_year", "property_id", "raw_json", "normalized_data", "prop_list_id")
    }

    "prop-temp" = [PSCustomObject]@{
        TableName      = "prop_temp"
        TargetFile     = "$($script:CadPrefix).$($script:TaxYear).temp.sqlite"
        IsTemporary    = $true
        CreateTableSql = @"
CREATE TABLE IF NOT EXISTS prop_temp (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    quick_ref TEXT NOT NULL,
    tax_year INTEGER NOT NULL,
    subdivision TEXT,
    part_html TEXT,
    part_details TEXT,
    part_values TEXT,
    part_taxing_jurisdiction TEXT,
    part_improvement_building TEXT,
    part_land TEXT,
    part_roll_value_history TEXT,
    part_deed_history TEXT,
    decomposed_status TEXT,
    prop_list_id INTEGER,
    prop_detail_id INTEGER,
    CONSTRAINT FK_temp_prop_list FOREIGN KEY (prop_list_id) 
        REFERENCES prop_list(id) ON DELETE CASCADE,
    CONSTRAINT FK_temp_prop_detail FOREIGN KEY (prop_detail_id) 
        REFERENCES prop_detail(id) ON DELETE CASCADE,
    CONSTRAINT UQ_prop_temp_key UNIQUE (tax_year, quick_ref)
);
"@
        Columns        = @(
            "id", "quick_ref", "tax_year", "subdivision", 
            "part_html", "part_details", "part_values", 
            "part_taxing_jurisdiction", "part_improvement_building", 
            "part_land", "part_roll_value_history", "part_deed_history", 
            "decomposed_status", "prop_list_id", "prop_detail_id"
        )
    }
}

function Get-DistrictSchema {
<#
.SYNOPSIS
    Retrieves the deterministic schema definition for a specified table name.
.DESCRIPTION
    Accepts a standardized table name and returns a custom object containing the table name, 
    complete CREATE TABLE SQL statement, and column arrays.
.PARAMETER TableName
    The standardized table category ("lookup", "prop-list", "prop-detail", "prop-temp").
.OUTPUTS
    [PSCustomObject] containing schema metadata and creation scripts.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("lookup", "prop-list", "prop-detail", "prop-temp")]
        [string]$TableName
    )

    if (-not $script:DistrictSchemas.ContainsKey($TableName)) {
        throw "Standardized table name '$TableName' not found in district schema definitions."
    }

    return $script:DistrictSchemas[$TableName]
}

function Get-Lookups {
<#
.SYNOPSIS
    Retrieves the module-level lookup endpoint registry definitions.
.DESCRIPTION
    Returns the full array of lookup definition objects, or a single matched object 
    if a specific lookup term is provided.
.PARAMETER Term
    Optional lookup term identifier (e.g., "abstracts", "subdivisions").
.OUTPUTS
    [PSCustomObject] or [PSCustomObject[]] representing the target endpoint metadata.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Term
    )

    if ($PSBoundParameters.ContainsKey('Term')) {
        $match = $script:LookupRegistry | Where-Object { $_.Term -eq $Term }
        return $match
    }

    return $script:LookupRegistry
}

function Build-Lookup-Read {
<#
.SYNOPSIS
    Generates a parameterized SQL statement command object to query stored lookup values.
.DESCRIPTION
    Constructs a command descriptor containing the SQL query string and parameter mappings 
    to retrieve cached lookup records for a given term and tax year from the database engine.
.PARAMETER Term
    The lookup classification term being queried.
.PARAMETER TaxYear
    The tax year scope for the query (defaults to 2026).
.OUTPUTS
    [PSCustomObject] containing 'Sql' string and 'Parameters' hashtable.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Term,
        [Parameter(Mandatory = $false)]
        [int]$TaxYear = 2026
    )

    $sql = "SELECT * FROM lookup WHERE lookup_type = @term AND tax_year = @year;"
    $parameters = @{
        '@term' = $Term
        '@year' = $TaxYear
    }

    return [PSCustomObject]@{
        Sql        = $sql
        Parameters = $parameters
    }
}

function Build-Lookup-Insert {
<#
.SYNOPSIS
    Builds insert command descriptors for storing lookup records into SQLite.
.DESCRIPTION
    Iterates through an array of lookup records, building parameterized INSERT OR IGNORE statements 
    along with warning handler metadata for handling duplicates gracefully without throwing execution errors.
.PARAMETER LookupName
    The name category of the lookup dataset.
.PARAMETER LookupData
    An array of lookup record objects to be processed.
.PARAMETER TaxYear
    The target tax year for the records.
.OUTPUTS
    [PSCustomObject[]] representing a batch of command descriptors ready for common engine execution.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LookupName,
        [Parameter(Mandatory = $true)]
        [array]$LookupData,
        [Parameter(Mandatory = $true)]
        [int]$TaxYear
    )

    $commands = @()

    foreach ($item in $LookupData) {
        $sql = @"
INSERT OR IGNORE INTO lookup (tax_year, lookup_type, text, code, family, section, name, prop_count) 
VALUES (@tax_year, @lookup_type, @text, @code, @family, @section, @name, @prop_count);
"@
        $parameters = @{
            '@tax_year'    = $TaxYear
            '@lookup_type' = $LookupName
            '@text'        = $item.text
            '@code'        = $item.code
            '@family'      = $item.family
            '@section'     = $item.section
            '@name'        = $item.name
            '@prop_count'  = if ($item.prop_count) { $item.prop_count } else { 0 }
        }

        $commands += [PSCustomObject]@{
            Sql            = $sql
            Parameters     = $parameters
            WarningHandler = "If changes == 0, Write-Warning 'Lookup item [$($item.text)] already exists and could not be inserted.'"
        }
    }

    return $commands
}

function Invoke-Fetch-Lookup {
<#
.SYNOPSIS
    Resolves live lookup data values from the remote district web endpoint using fetch-ps.
.DESCRIPTION
    Looks up the endpoint path associated with the specified term, constructs the target URI, 
    and invokes fetch-ps structured request handling to retrieve and normalize the payload.
.PARAMETER Term
    The lookup category term to resolve (e.g., "subdivisions").
.PARAMETER BaseUrl
    The base web URL for the CAD search system (defaults to https://esearch.fbcad.org).
.OUTPUTS
    [array] or [PSCustomObject] containing the remote response payload data.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Term,
        [Parameter(Mandatory = $false)]
        [string]$BaseUrl
    )

    $lookupConfig = Get-Lookups -Term $Term
    if (-not $lookupConfig) {
        throw "Lookup term '$Term' is not defined in the module registry."
    }

    $resolvedBaseUrl = if ($PSBoundParameters.ContainsKey('BaseUrl') -and $BaseUrl) { 
        $BaseUrl 
    } else { 
        "https://esearch.fbcad.org" 
    }

    $targetUrl = "$resolvedBaseUrl$($lookupConfig.Path)"
    
    $requestParams = @{
        InputType = "JSON"
        Method    = "GET"
    }

    $result = Invoke-StructuredRequest -Url $targetUrl -Params $requestParams

    if (-not $result.Success) {
        throw "Failed to fetch lookup endpoint [$Term] from $targetUrl. Status: $($result.StatusCode)"
    }

    return $result.Data
}

Export-ModuleMember -Function Get-DistrictSchema, Get-Lookups, Build-Lookup-Read, Invoke-Fetch-Lookup, Build-Lookup-Insert