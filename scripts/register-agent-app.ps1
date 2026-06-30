<#
.SYNOPSIS
    Creates an Entra ID app registration for agent sign-in to the verification portal.

.PARAMETER TenantId
    Entra ID tenant ID.

.PARAMETER AppName
    Display name for the app registration.

.PARAMETER RedirectUri
    Sign-in redirect URI, typically https://<app-name>.azurewebsites.net/signin-oidc

.EXAMPLE
    .\register-agent-app.ps1 -TenantId "<tenant-id>" -AppName "Verified Helpdesk Portal" -RedirectUri "https://my-app.azurewebsites.net/signin-oidc"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [string]$RedirectUri
)

$ErrorActionPreference = "Stop"

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All" -NoWelcome

$params = @{
    displayName = $AppName
    signInAudience = "AzureADMyOrg"
    web = @{
        redirectUris = @($RedirectUri)
        implicitGrantSettings = @{
            enableIdTokenIssuance = $true
        }
    }
}

$app = New-MgApplication @params
Write-Host "Created app registration."
Write-Host "Client ID: $($app.AppId)"
Write-Host "Set AzureAd__ClientId and AzureAd__TenantId in App Service configuration."
