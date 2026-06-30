<#
.SYNOPSIS
    Registers Azure resource providers required by the Verified Helpdesk ARM template.

.PARAMETER Wait
    Wait for each provider registration to complete before continuing.

.EXAMPLE
    .\register-azure-providers.ps1 -Wait
#>
[CmdletBinding()]
param(
    [switch]$Wait
)

$ErrorActionPreference = "Stop"

$providers = @(
    "Microsoft.OperationalInsights",
    "Microsoft.Insights",
    "Microsoft.Web"
)

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed. Install from https://learn.microsoft.com/cli/azure/install-azure-cli or use Azure Cloud Shell."
}

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    throw "Not logged in to Azure CLI. Run 'az login' and select the target subscription with 'az account set --subscription <id>'."
}

Write-Host "Subscription: $($account.name) ($($account.id))"
Write-Host ""

foreach ($namespace in $providers) {
    $registerArgs = @("provider", "register", "--namespace", $namespace)
    if ($Wait) {
        $registerArgs += "--wait"
    }

    Write-Host "Registering $namespace..."
    az @registerArgs | Out-Null

    az provider show -n $namespace --query "{Namespace:namespace, State:registrationState}" -o table
    Write-Host ""
}

Write-Host "Done. All providers should show State=Registered before deploying the ARM template."
