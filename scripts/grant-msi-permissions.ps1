<#
.SYNOPSIS
    Grants the App Service managed identity permissions for Verified ID and Microsoft Graph.

.PARAMETER TenantId
    Entra ID tenant ID.

.PARAMETER AppName
    App Service name (used to look up the managed identity service principal).

.EXAMPLE
    .\grant-msi-permissions.ps1 -TenantId "<tenant-id>" -AppName "my-verified-helpdesk"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppName
)

$ErrorActionPreference = "Stop"

$VerifiedIdAppId = "3db474b9-6a0c-4840-96ac-1fceb342124f"
$GraphAppId = "00000003-0000-0000-c000-000000000000"

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -TenantId $TenantId -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome

$msi = Get-MgServicePrincipal -Filter "displayName eq '$AppName'"
if (-not $msi) {
    throw "Managed identity service principal not found for app '$AppName'. Enable System assigned identity and retry."
}

Write-Host "Assigning Verified ID permission..."
$vid = Get-MgServicePrincipal -Filter "appId eq '$VerifiedIdAppId'"
$vidRole = ($vid.AppRoles | Where-Object { $_.Value -eq "VerifiableCredential.Create.PresentRequest" }).Id
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $vid.Id -AppRoleId $vidRole | Out-Null

Write-Host "Assigning Microsoft Graph GroupMember.Read.All permission..."
$graph = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$graphRole = ($graph.AppRoles | Where-Object { $_.Value -eq "GroupMember.Read.All" }).Id
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $graph.Id -AppRoleId $graphRole | Out-Null

Write-Host "Permissions assigned successfully for '$AppName'."
