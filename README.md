# Verified Helpdesk

Bidirectional identity verification for IT helpdesk calls using [Microsoft Entra Verified ID](https://learn.microsoft.com/en-us/entra/verified-id/). Agents and callers each present the managed **VerifiedEmployee** credential from Microsoft Authenticator. Agent authorization is enforced via live **Microsoft Graph** group membership — no separate agent credential.

Based on the Microsoft [`6-woodgrove-helpdesk`](https://github.com/Azure-Samples/active-directory-verifiable-credentials-dotnet/tree/main/6-woodgrove-helpdesk) sample, extended for agent-first bidirectional verification and fixed for standalone Azure App Service deployment.

## Features

- Agent Entra ID sign-in before starting a session
- Agent presents VerifiedEmployee credential first
- Graph `checkMemberGroups` authorization against your IT Helpdesk security group
- Caller link (`/caller/{sessionId}`) shows verified agent identity, then prompts caller verification
- App Service **Managed Identity** for Verified ID and Graph (no API secrets)
- Application Insights audit events per verification
- Configurable organization branding via app settings
- Face Check optional (disabled by default)

## Architecture

```
Agent (signed in) → present VC → Graph group check → share caller link
Caller (anonymous) → sees verified agent → present VC → session complete → audit event
```

See [Verified helpdesk with Microsoft Entra Verified ID](https://learn.microsoft.com/en-us/entra/verified-id/helpdesk-with-verified-id) for the Microsoft reference pattern.

## Prerequisites

Before deploying:

1. **Entra ID tenant** with a verified custom domain (for Verified ID Quick setup)
2. **Microsoft Entra Verified ID** configured with managed **VerifiedEmployee** and MyAccount issuance enabled  
   [Quick setup guide](https://learn.microsoft.com/en-us/entra/verified-id/verifiable-credentials-configure-tenant-quick)
3. **IT Helpdesk security group** — record its object ID; add helpdesk agents as members
4. **Azure subscription**
5. **GitHub repository** hosting this code (for Deploy to Azure source control)
6. **App registration** for agent sign-in (see [Post-deploy configuration](#post-deploy-configuration))

Record your **issuer DID** from Entra admin center → Verified ID → Settings.

## Deploy to Azure

Complete prerequisites first, then deploy:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fzlowes%2FVerified-Helpdesk%2Fmain%2FARMTemplate%2Ftemplate.json)

### Quick start for deployers

1. Record your issuer **DID**, IT Helpdesk **group object ID**, and **tenant ID** from Entra ID
2. Choose a globally unique **webAppName** (becomes `https://<webAppName>.azurewebsites.net`)
3. Create an app registration (if needed) with [`scripts/register-agent-app.ps1`](scripts/register-agent-app.ps1) — redirect URI: `https://<webAppName>.azurewebsites.net/signin-oidc`
4. Click **Deploy to Azure** above and enter: `webAppName`, `DidAuthority`, `ITHelpdeskGroupId`, `AzureAdTenantId`, `AzureAdClientId`
5. After deploy, authorize GitHub in App Service → Deployment Center if prompted
6. Run [`scripts/grant-msi-permissions.ps1`](scripts/grant-msi-permissions.ps1) with your tenant ID and App Service name

To use your own fork later, change the `repoURL` parameter during deploy or update the Deploy button URL in your fork's README.

### ARM template parameters

| Parameter | Description |
|-----------|-------------|
| `webAppName` | Globally unique App Service name |
| `repoURL` | GitHub repo URL (default: `https://github.com/zlowes/Verified-Helpdesk.git`) |
| `branch` | Branch to deploy (default: `main`) |
| `DidAuthority` | Your Verified ID issuer DID |
| `ITHelpdeskGroupId` | Object ID of the IT Helpdesk security group |
| `AzureAdTenantId` | Entra ID tenant ID |
| `AzureAdClientId` | App registration client ID for agent sign-in |
| `companyName` | Organization name shown in the portal (default: `Your Organization`) |

The template provisions:

- App Service Plan (Basic B1)
- Web App with system-assigned managed identity
- Application Insights
- GitHub source control integration
- Required app settings

### Why standalone deployment fixes the sample error

The upstream Microsoft monorepo uses a root `.deployment` file that runs `cd %PROJECT% && deploy.cmd`, but the `6-woodgrove-helpdesk` subfolder has no `deploy.cmd`. Kudu fails with:

```
'deploy.cmd' is not recognized as an internal or external command
```

This repository is a **standalone app at the repo root** with its own [`deploy.cmd`](deploy.cmd) and [`.deployment`](.deployment) file — no `PROJECT` subfolder required.

## Post-deploy configuration

### 1. Connect GitHub deployment

After ARM deployment, complete GitHub authorization in App Service → Deployment Center if prompted.

### 2. Grant Managed Identity permissions

The app's **system-assigned managed identity** needs two application permissions (not delegated):

| API | App role | Purpose |
|-----|----------|---------|
| Verified ID Request Service (`3db474b9-6a0c-4840-96ac-1fceb342124f`) | `VerifiableCredential.Create.PresentRequest` | Create presentation requests |
| Microsoft Graph (`00000003-0000-0000-c000-000000000000`) | `GroupMember.Read.All` | Check IT Helpdesk group membership |

You need an Entra ID role that can assign app roles (for example **Cloud Application Administrator** or **Privileged Role Administrator**).

#### Option A: Azure Cloud Shell (recommended)

1. Open [Azure Portal](https://portal.azure.com) and select **Cloud Shell** (PowerShell mode).
2. Confirm **System assigned identity** is enabled on your App Service: **App Service → Identity → System assigned → On**. Wait a minute for the identity to propagate.
3. Install the Microsoft Graph module if Cloud Shell does not already have it:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

4. Set your values and run the commands below. Replace `<your-tenant-id>` and `<your-app-service-name>` with your tenant ID and the App Service name from deployment.

```powershell
$TenantId = "<your-tenant-id>"
$AppName  = "<your-app-service-name>"

$VerifiedIdAppId = "3db474b9-6a0c-4840-96ac-1fceb342124f"
$GraphAppId        = "00000003-0000-0000-c000-000000000000"

Connect-MgGraph -TenantId $TenantId -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome

$msi = Get-MgServicePrincipal -Filter "displayName eq '$AppName'"
if (-not $msi) {
    throw "Managed identity not found for '$AppName'. Enable System assigned identity on the App Service and wait a minute, then retry."
}

# Verified ID: VerifiableCredential.Create.PresentRequest
$vid = Get-MgServicePrincipal -Filter "appId eq '$VerifiedIdAppId'"
$vidRole = ($vid.AppRoles | Where-Object { $_.Value -eq "VerifiableCredential.Create.PresentRequest" }).Id
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $vid.Id -AppRoleId $vidRole

# Microsoft Graph: GroupMember.Read.All
$graph = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$graphRole = ($graph.AppRoles | Where-Object { $_.Value -eq "GroupMember.Read.All" }).Id
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $graph.Id -AppRoleId $graphRole

Write-Host "Permissions assigned for '$AppName'."
```

5. Verify assignments in **Entra admin center → Enterprise applications** — search for your App Service name and open **Permissions**.

**Alternative in Cloud Shell:** clone this repo and run the helper script:

```powershell
git clone https://github.com/zlowes/Verified-Helpdesk.git
cd Verified-Helpdesk
.\scripts\grant-msi-permissions.ps1 -TenantId "<your-tenant-id>" -AppName "<your-app-service-name>"
```

#### Option B: Local PowerShell

From a clone of this repository:

```powershell
.\scripts\grant-msi-permissions.ps1 -TenantId "<your-tenant-id>" -AppName "<your-app-service-name>"
```

Requires `Install-Module Microsoft.Graph`.

### 3. Register agent sign-in app (if not done pre-deploy)

```powershell
.\scripts\register-agent-app.ps1 `
  -TenantId "<your-tenant-id>" `
  -AppName "Verified Helpdesk Portal" `
  -RedirectUri "https://<your-app-name>.azurewebsites.net/signin-oidc"
```

Set the returned client ID in App Service configuration as `AzureAd__ClientId`.

### 4. Verify app settings

Confirm these settings in App Service → Configuration (see [`appservice-config-template.json`](appservice-config-template.json)):

| Setting | Purpose |
|---------|---------|
| `VerifiedID__DidAuthority` | Issuer DID |
| `VerifiedID__ManagedIdentity` | `true` on Azure |
| `AppSettings__ITHelpdeskGroupId` | Helpdesk group object ID |
| `AzureAd__TenantId` / `AzureAd__ClientId` | Agent sign-in |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Set by ARM template |

## Customization (branding)

Set these in App Service configuration — no code changes required:

| Setting | Default | Purpose |
|---------|---------|---------|
| `AppSettings__CompanyName` | `Your Organization` | Header display name |
| `AppSettings__CompanyLogo` | *(empty)* | Logo URL; hidden when empty |
| `AppSettings__PortalTitle` | `Verified Helpdesk` | Browser title |
| `AppSettings__AuthorizedAgentLabel` | `Authorized Helpdesk Agent` | Badge shown to callers |
| `VerifiedID__client_name` | `Helpdesk Verification` | Verified ID presentation label |

Optional Teams notification: set `AppSettings__UseTeamsWebhook` to `true` and `AppSettings__TeamsWebhookURL` to your incoming webhook URL.

Optional Face Check: set `VerifiedID__EnableFaceCheck` to `true`.

## Local development

1. Install [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
2. Copy `appsettings.json` values into User Secrets or `appsettings.Development.json` (gitignored)
3. For local Verified ID/Graph calls without MSI, set `VerifiedID__ManagedIdentity` to `false` and provide `VerifiedID__TenantId`, `VerifiedID__ClientId`, and `VerifiedID__ClientSecret`
4. Run:

```bash
dotnet run --project VerifiedHelpdesk.csproj
```

## Usage

### Agent flow

1. Open the portal and sign in with your work account
2. Click **Start Verification**
3. Scan the QR code with Microsoft Authenticator and share your VerifiedEmployee credential
4. After group authorization succeeds, copy the caller link and send it to the employee (SMS, email, Teams, etc.)
5. Wait for caller verification to complete

### Caller flow

1. Open the link shared by the agent (`/caller/{sessionId}`)
2. Confirm the verified agent name and authorization badge
3. Scan the QR code and share your VerifiedEmployee credential
4. See confirmation when verification completes

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| Default Azure placeholder page | Deploy failed | Check Deployment Center logs; confirm `deploy.cmd` exists at repo root |
| `deploy.cmd` not recognized | Monorepo `.deployment` without local `deploy.cmd` | Use this standalone repo, not the upstream subfolder |
| Verified ID API 401/403 | MSI permissions missing | Run the [Cloud Shell commands](#option-a-azure-cloud-shell-recommended) or `grant-msi-permissions.ps1` |
| Agent not authorized | User not in helpdesk group | Add agent to IT Helpdesk group; verify `AppSettings__ITHelpdeskGroupId` |
| Sign-in fails | App registration misconfigured | Verify redirect URI matches `https://<app>.azurewebsites.net/signin-oidc` |
| Session expired | In-memory cache TTL | Restart verification; increase `AppSettings__CacheExpiresInSeconds` if needed |

View logs: App Service → **Log stream**, or Application Insights → **Logs** (query `customEvents` for `VerificationCompleted` / `VerificationFailed`).

## Project structure

```
Verified-Helpdesk/
├── ARMTemplate/template.json   # Deploy to Azure
├── deploy.cmd / .deployment    # Kudu custom deploy
├── Controllers/                # Agent, Caller, API, Callback
├── Services/                   # Session, Graph, Audit, Verified ID
├── scripts/                    # MSI and app registration helpers
└── Views/                      # Agent and caller portals
```

## License and attribution

Application code is derived from [Azure-Samples/active-directory-verifiable-credentials-dotnet](https://github.com/Azure-Samples/active-directory-verifiable-credentials-dotnet) (MIT License).

Microsoft documentation:

- [Verified helpdesk pattern](https://learn.microsoft.com/en-us/entra/verified-id/helpdesk-with-verified-id)
- [VerifiedEmployee credential](https://learn.microsoft.com/en-us/entra/verified-id/how-to-use-quickstart-verifiedemployee)
- [App Service Managed Identity](https://learn.microsoft.com/en-us/azure/app-service/overview-managed-identity)
