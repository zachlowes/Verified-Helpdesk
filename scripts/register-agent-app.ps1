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

function Get-GraphErrorMessages {
    param([System.Exception]$Exception)

    $messages = @()
    if ($Exception.InnerExceptions) {
        $messages += $Exception.InnerExceptions | ForEach-Object { $_.Message }
    }
    if ($Exception.InnerException) {
        $messages += $Exception.InnerException.Message
    }
    $messages += $Exception.Message
    return ($messages | Where-Object { $_ } | Select-Object -Unique)
}

function Write-GraphInnerErrors {
    param([System.Exception]$Exception)

    foreach ($message in (Get-GraphErrorMessages -Exception $Exception)) {
        Write-Host "  $message" -ForegroundColor Red
    }
}

function Write-GraphFailureHints {
    param([string[]]$Messages)

    $combined = ($Messages -join " ")
    if ($combined -match "Authorization_RequestDenied|Insufficient privileges|403|401") {
        Write-Host ""
        Write-Host "Permission fix: sign in with Cloud Application Administrator (or Global Administrator),"
        Write-Host "accept admin consent for Application.ReadWrite.All, then re-run this script."
        Write-Host "Or create the app manually in Entra admin center -> App registrations -> New registration."
    }
    elseif ($combined -match "Could not load file or assembly|FileNotFoundException|TypeLoadException|MissingMethodException") {
        Write-Host ""
        Write-Host "Module fix: close this PowerShell window and use a fresh one. Then run:"
        Write-Host "  Get-InstalledModule Microsoft.Graph* | Uninstall-Module -AllVersions -Force"
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser -Force"
        Write-Host "Do not import Exchange Online or PnP modules before running this script."
    }
}

function Invoke-GraphCommand {
    param(
        [string]$Action,
        [scriptblock]$Command
    )

    try {
        return & $Command
    }
    catch {
        Write-Host "$Action failed." -ForegroundColor Red
        Write-GraphInnerErrors -Exception $_.Exception
        Write-GraphFailureHints -Messages (Get-GraphErrorMessages -Exception $_.Exception)
        throw
    }
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    throw "Microsoft.Graph module not found. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
}

$duplicateModules = Get-Module Microsoft.Graph* -ListAvailable | Group-Object Name | Where-Object { $_.Count -gt 1 }
if ($duplicateModules) {
    Write-Warning "Multiple Microsoft.Graph module versions detected. This often causes 'One or more errors occurred'."
    foreach ($group in $duplicateModules) {
        $versions = ($group.Group | Sort-Object Version -Descending | ForEach-Object { $_.Version.ToString() }) -join ", "
        Write-Warning "  $($group.Name): $versions"
    }
    Write-Warning "Reinstall in a fresh PowerShell window before continuing (see README troubleshooting)."
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All" -NoWelcome

$context = Get-MgContext
if (-not $context) {
    throw "Not connected to Microsoft Graph. Connect-MgGraph did not establish a session."
}

Write-Host "Signed in as: $($context.Account) (tenant: $($context.TenantId))"

$requiredScope = "Application.ReadWrite.All"
if ($context.Scopes -notcontains $requiredScope) {
    throw "Missing required scope '$requiredScope'. Reconnect with: Connect-MgGraph -Scopes '$requiredScope'"
}

Write-Host "Checking for existing app registration..."
$escapedAppName = $AppName.Replace("'", "''")
$existing = Invoke-GraphCommand -Action "Lookup existing app registration" -Command {
    Get-MgApplication -Filter "displayName eq '$escapedAppName'"
}

if ($existing) {
    Write-Host "App registration '$AppName' already exists."
    Write-Host "Client ID: $($existing.AppId)"
    Write-Host "Set AzureAd__ClientId and AzureAd__TenantId in App Service configuration."
    Write-Host "Confirm redirect URI '$RedirectUri' is configured under Authentication in Entra admin center."
    exit 0
}

Write-Host "Creating app registration..."
$app = Invoke-GraphCommand -Action "Create app registration" -Command {
    New-MgApplication `
        -DisplayName $AppName `
        -SignInAudience "AzureADMyOrg" `
        -Web @{
            RedirectUris = $RedirectUri
            ImplicitGrantSettings = @{
                EnableIdTokenIssuance = $true
            }
        }
}

Write-Host "Created app registration."
Write-Host "Client ID: $($app.AppId)"
Write-Host "Set AzureAd__ClientId and AzureAd__TenantId in App Service configuration."
