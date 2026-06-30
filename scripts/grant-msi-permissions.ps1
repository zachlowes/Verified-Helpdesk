<#
.SYNOPSIS
    Grants the App Service managed identity permissions for Verified ID.

.PARAMETER TenantId
    Entra ID tenant ID.

.PARAMETER AppName
    App Service name (used to look up the managed identity service principal).

.PARAMETER ServicePrincipalId
    Optional object (principal) ID from App Service -> Identity. Use when display-name lookup
    finds zero or multiple service principals.

.EXAMPLE
    .\grant-msi-permissions.ps1 -TenantId "<tenant-id>" -AppName "my-verified-helpdesk"

.EXAMPLE
    .\grant-msi-permissions.ps1 -TenantId "<tenant-id>" -AppName "my-verified-helpdesk" -ServicePrincipalId "<object-id>"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalId
)

$ErrorActionPreference = "Stop"

$VerifiedIdAppId = "3db474b9-6a0c-4840-96ac-1fceb342124f"

function ConvertTo-GraphId {
    param(
        [object]$Value,
        [string]$Label
    )

    if ($null -eq $Value) {
        throw "$Label is null."
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            throw "$Label is null."
        }
        if ($items.Count -gt 1) {
            $joined = ($items | ForEach-Object { $_.ToString() }) -join ", "
            throw "$Label resolved to multiple values: $joined"
        }
        $Value = $items[0]
    }

    $text = if ($Value -is [string]) { $Value.Trim() } else { $Value.ToString().Trim() }
    if ($text -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "$Label is not a valid GUID: '$text'"
    }

    return $text.ToLower()
}

function Get-GraphServicePrincipalsByFilter {
    param(
        [string]$Description,
        [string]$Filter
    )

    $uri = "v1.0/servicePrincipals?`$filter=$([uri]::EscapeDataString($Filter))"
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri
    $results = @($response.value | Where-Object { $null -ne $_ })

    if ($results.Count -eq 0) {
        throw "$Description not found (filter: $Filter)."
    }
    if ($results.Count -gt 1) {
        $ids = ($results | ForEach-Object { $_.id }) -join ", "
        throw "$Description returned $($results.Count) matches. Pass -ServicePrincipalId with the Object ID from App Service -> Identity. Matching IDs: $ids"
    }

    return $results[0]
}

function Get-GraphServicePrincipalByAppId {
    param(
        [string]$Description,
        [string]$AppId
    )

    try {
        return Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals(appId='$AppId')"
    }
    catch {
        throw "$Description not found for appId '$AppId'. $($_.Exception.Message)"
    }
}

function Get-GraphAppRoleId {
    param(
        [object]$ServicePrincipal,
        [string]$RoleValue,
        [string]$ApiName
    )

    $roles = @(
        $ServicePrincipal.appRoles |
            Where-Object { $_.value -eq $RoleValue -and $_.allowedMemberTypes -contains "Application" }
    )

    if ($roles.Count -eq 0) {
        throw "App role '$RoleValue' not found on $ApiName service principal."
    }
    if ($roles.Count -gt 1) {
        throw "App role '$RoleValue' matched multiple roles on $ApiName service principal."
    }

    return ConvertTo-GraphId $roles[0].id "App role ID for $RoleValue"
}

function Add-GraphAppRoleAssignment {
    param(
        [string]$ManagedIdentityId,
        [string]$ResourceId,
        [string]$AppRoleId,
        [string]$PermissionLabel
    )

    $body = @{
        principalId = $ManagedIdentityId
        resourceId  = $ResourceId
        appRoleId   = $AppRoleId
    }

    try {
        Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals/$ManagedIdentityId/appRoleAssignments" -Body $body | Out-Null
        Write-Host "  Assigned $PermissionLabel."
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'Permission being assigned already exists|Authorization_RequestDenied.*already exists') {
            Write-Host "  $PermissionLabel already assigned, skipping."
            return
        }

        throw "Failed to assign $PermissionLabel. $message"
    }
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw "Microsoft.Graph module not found. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
}

$duplicateModules = Get-Module Microsoft.Graph* -ListAvailable | Group-Object Name | Where-Object { $_.Count -gt 1 }
if ($duplicateModules) {
    Write-Warning "Multiple Microsoft.Graph module versions detected. This often causes Graph cmdlet errors."
    foreach ($group in $duplicateModules) {
        $versions = ($group.Group | Sort-Object Version -Descending | ForEach-Object { $_.Version.ToString() }) -join ", "
        Write-Warning "  $($group.Name): $versions"
    }
    Write-Warning "Reinstall in a fresh PowerShell window before continuing (see README troubleshooting)."
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -TenantId $TenantId -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome

$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Connect-MgGraph did not establish a session."
}

Write-Host "Signed in as: $($context.Account) (tenant: $($context.TenantId))"

$requiredScopes = @("Application.Read.All", "AppRoleAssignment.ReadWrite.All")
foreach ($scope in $requiredScopes) {
    if ($context.Scopes -notcontains $scope) {
        throw "Missing required scope '$scope'. Reconnect with: Connect-MgGraph -Scopes '$($requiredScopes -join "', '")'"
    }
}

if ($ServicePrincipalId) {
    Write-Host "Using provided service principal ID..."
    $msiId = ConvertTo-GraphId $ServicePrincipalId "Service principal ID"
    $null = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals/$msiId"
}
else {
    Write-Host "Looking up managed identity for '$AppName'..."
    $escapedAppName = $AppName.Replace("'", "''")
    $filter = "displayName eq '$escapedAppName' and servicePrincipalType eq 'ManagedIdentity'"
    $msi = Get-GraphServicePrincipalsByFilter -Description "Managed identity for app '$AppName'" -Filter $filter
    $msiId = ConvertTo-GraphId $msi.id "Managed identity object ID"
}

Write-Host "Managed identity object ID: $msiId"

Write-Host "Assigning Verified ID permission..."
$vid = Get-GraphServicePrincipalByAppId -Description "Verified ID Request Service" -AppId $VerifiedIdAppId
$vidId = ConvertTo-GraphId $vid.id "Verified ID service principal ID"
$vidRole = Get-GraphAppRoleId -ServicePrincipal $vid -RoleValue "VerifiableCredential.Create.PresentRequest" -ApiName "Verified ID Request Service"
Add-GraphAppRoleAssignment -ManagedIdentityId $msiId -ResourceId $vidId -AppRoleId $vidRole -PermissionLabel "VerifiableCredential.Create.PresentRequest"

Write-Host "Permissions assigned successfully for '$AppName'."
