<#
.SYNOPSIS
    Grants the App Service managed identity permissions for Verified ID and Microsoft Graph.

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
$GraphAppId = "00000003-0000-0000-c000-000000000000"

function Get-SingleServicePrincipal {
    param(
        [string]$Description,
        [string]$Filter
    )

    $results = @(Get-MgServicePrincipal -Filter $Filter)
    if ($results.Count -eq 0) {
        throw "$Description not found (filter: $Filter)."
    }
    if ($results.Count -gt 1) {
        $ids = ($results | ForEach-Object { $_.Id }) -join ", "
        throw "$Description returned $($results.Count) matches. Pass -ServicePrincipalId with the Object ID from App Service -> Identity. Matching IDs: $ids"
    }

    return $results[0]
}

function Get-AppRoleId {
    param(
        [object]$ServicePrincipal,
        [string]$RoleValue,
        [string]$ApiName
    )

    $role = @($ServicePrincipal.AppRoles | Where-Object { $_.Value -eq $RoleValue })[0]
    if (-not $role -or -not $role.Id) {
        throw "App role '$RoleValue' not found on $ApiName service principal."
    }

    return [string]$role.Id
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
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
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

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
    $msi = Get-MgServicePrincipal -ServicePrincipalId $ServicePrincipalId
    if (-not $msi) {
        throw "Service principal '$ServicePrincipalId' not found."
    }
    $msiId = [string]$msi.Id
}
else {
    Write-Host "Looking up managed identity for '$AppName'..."
    $escapedAppName = $AppName.Replace("'", "''")
    $filter = "displayName eq '$escapedAppName' and servicePrincipalType eq 'ManagedIdentity'"
    $msi = Get-SingleServicePrincipal -Description "Managed identity for app '$AppName'" -Filter $filter
    $msiId = [string]$msi.Id
}

if (-not $msiId) {
    throw "Managed identity service principal has no object ID. Enable System assigned identity on the App Service, wait about one minute, then retry."
}

Write-Host "Managed identity object ID: $msiId"

Write-Host "Assigning Verified ID permission..."
$vid = Get-SingleServicePrincipal -Description "Verified ID Request Service" -Filter "appId eq '$VerifiedIdAppId'"
$vidId = [string]$vid.Id
$vidRole = Get-AppRoleId -ServicePrincipal $vid -RoleValue "VerifiableCredential.Create.PresentRequest" -ApiName "Verified ID Request Service"
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msiId `
    -PrincipalId $msiId -ResourceId $vidId -AppRoleId $vidRole | Out-Null

Write-Host "Assigning Microsoft Graph GroupMember.Read.All permission..."
$graph = Get-SingleServicePrincipal -Description "Microsoft Graph" -Filter "appId eq '$GraphAppId'"
$graphId = [string]$graph.Id
$graphRole = Get-AppRoleId -ServicePrincipal $graph -RoleValue "GroupMember.Read.All" -ApiName "Microsoft Graph"
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msiId `
    -PrincipalId $msiId -ResourceId $graphId -AppRoleId $graphRole | Out-Null

Write-Host "Permissions assigned successfully for '$AppName'."
