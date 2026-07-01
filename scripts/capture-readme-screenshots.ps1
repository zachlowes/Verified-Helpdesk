<#
.SYNOPSIS
  Captures README demo workflow GIF for the Verified Helpdesk portal.

.DESCRIPTION
  Default mode uses static staging HTML (scripts/screenshot-staging/) that mirrors
  the live portal UI with Contoso demo data. Produces ReadmeFiles/demo-workflow.gif.
  No Entra sign-in or Verified ID required.

  Optional live mode (-BaseUrl) is documented for manual capture from a running app.
  See the LIVE CAPTURE section below for console snippets and callback payloads.

.PARAMETER BaseUrl
  Live app URL (e.g. https://localhost:5001). Omit to use staging HTML.

.PARAMETER SkipInstall
  Skip pip install and Playwright browser install.

.EXAMPLE
  .\scripts\capture-readme-screenshots.ps1

.EXAMPLE
  .\scripts\capture-readme-screenshots.ps1 -SkipInstall
#>
[CmdletBinding()]
param(
    [string] $BaseUrl,
    [switch] $SkipInstall
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ReadmeFiles = Join-Path $RepoRoot "ReadmeFiles"

if (-not (Test-Path $ReadmeFiles)) {
    New-Item -ItemType Directory -Path $ReadmeFiles | Out-Null
}

Push-Location $ScriptDir
try {
    if (-not $SkipInstall) {
        Write-Host "Installing Python dependencies (playwright, pillow)..."
        python -m pip install playwright pillow --quiet
        if ($LASTEXITCODE -ne 0) { throw "pip install failed with exit code $LASTEXITCODE" }
        Write-Host "Installing Playwright Chromium..."
        python -m playwright install chromium
        if ($LASTEXITCODE -ne 0) { throw "playwright install chromium failed with exit code $LASTEXITCODE" }
    }

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        Write-Host "Capturing workflow GIF from staging HTML (1280x900 viewport, 720px output)..."
        python capture-screenshots.py
    }
    else {
        Write-Host "Live capture mode is not yet automated. Use staging mode (default) or capture manually:"
        Write-Host "  1. Sign in at $BaseUrl/Agent"
        Write-Host "  2. Run browser console snippets documented in this script (LIVE CAPTURE section)"
        Write-Host "  3. Assemble frames into ReadmeFiles/demo-workflow.gif"
        exit 1
    }

    $gifPath = Join-Path $ReadmeFiles "demo-workflow.gif"
    if (Test-Path $gifPath) {
        $sizeKb = [math]::Round((Get-Item $gifPath).Length / 1KB, 1)
        Write-Host "Done. Workflow GIF written to $gifPath ($sizeKb KB)"
    }
    else {
        throw "Expected output not found: $gifPath"
    }
}
finally {
    Pop-Location
}

<#
================================================================================
LIVE CAPTURE (optional) — browser DevTools on /Agent after sign-in
================================================================================

Prerequisites:
  - dotnet run with appsettings.Development.json (AzureAd + AppSettings:CompanyName=Contoso)
  - Viewport 1280x900, 100% zoom

Agent console snippets:

  // Step 2
  showStep("step-agent");
  agentQr.makeCode("https://verify.example/demo");
  document.getElementById("agent-status").textContent = "Waiting for your verification...";

  // Step 3
  showStep("step-caller-link");
  document.getElementById("verified-agent-name").textContent = "Alex Morgan";
  document.getElementById("caller-link").value = "https://helpdesk-demo.azurewebsites.net/caller/demo-session-id";
  document.getElementById("user-status").textContent = "Waiting for caller verification...";

  // Step 4
  showStep("step-complete");
  document.getElementById("verified-user-name").textContent = "Jordan Lee";
  document.getElementById("verified-user-mail").textContent = "jordan.lee@contoso.com";

Caller session seeding (after POST /api/session/start and creating presentation state):

  API-KEY: read from app startup log (Program.cs sets Environment API-KEY)

  Agent verified callback (state = sessionId from start):
  POST /api/verifier/presentationcallback
  Header: api-key: <API-KEY>
  Body:
  {
    "requestId": "demo-request-id",
    "requestStatus": "presentation_verified",
    "state": "<sessionId>",
    "verifiedCredentialsData": [{
      "type": ["VerifiedEmployee"],
      "claims": {
        "revocationId": "alex.morgan@contoso.com",
        "displayName": "Alex Morgan",
        "mail": "alex.morgan@contoso.com"
      }
    }]
  }

  Before agent callback, seed presentation state by clicking Start Verification once,
  or POST presentation-request (requires Verified ID configured).

  User verified callback (state = <sessionId>-user):
  Same payload with state "<sessionId>-user" and user claims:
    "displayName": "Jordan Lee", "mail": "jordan.lee@contoso.com", "revocationId": "jordan.lee@contoso.com"

  Caller QR mock on /caller/<sessionId>:
  userQr.makeCode("https://verify.example/demo");
  document.getElementById("user-status").textContent = "Scan the QR code with Microsoft Authenticator.";
================================================================================
#>
