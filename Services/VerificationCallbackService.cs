using Newtonsoft.Json;
using VerifiedHelpdesk.Models;

namespace VerifiedHelpdesk.Services;

public class VerificationCallbackService
{
    private readonly SessionService _sessionService;
    private readonly AuditService _auditService;
    private readonly IConfiguration _configuration;
    private readonly ILogger<VerificationCallbackService> _log;

    public VerificationCallbackService(
        SessionService sessionService,
        AuditService auditService,
        IConfiguration configuration,
        ILogger<VerificationCallbackService> log)
    {
        _sessionService = sessionService;
        _auditService = auditService;
        _configuration = configuration;
        _log = log;
    }

    public async Task ProcessPresentationCallbackAsync(string state, string callbackBody, string requestStatus)
    {
        var presentation = _sessionService.GetPresentationState(state);
        if (presentation == null)
        {
            _log.LogWarning("No presentation cache entry for state {State}", state);
            return;
        }

        presentation.Status = requestStatus;
        presentation.CallbackBody = callbackBody;
        _sessionService.SetPresentationState(state, presentation.SessionId, presentation.Phase, requestStatus, callbackBody);

        if (requestStatus != "presentation_verified")
        {
            if (requestStatus == "presentation_error")
            {
                FailSession(presentation.SessionId, "Presentation failed.");
            }
            return;
        }

        var callback = JsonConvert.DeserializeObject<CallbackEvent>(callbackBody);
        if (callback?.verifiedCredentialsData == null || callback.verifiedCredentialsData.Length == 0)
        {
            FailSession(presentation.SessionId, "No verified credential data received.");
            return;
        }

        if (presentation.Phase == VerificationPhases.Agent)
        {
            ProcessAgentPresentationAsync(presentation.SessionId, callback);
        }
        else if (presentation.Phase == VerificationPhases.User)
        {
            await ProcessUserPresentationAsync(presentation.SessionId, callback);
        }
    }

    private void ProcessAgentPresentationAsync(string sessionId, CallbackEvent callback)
    {
        var session = _sessionService.GetSession(sessionId);
        if (session == null)
        {
            return;
        }

        var claims = ExtractClaims(callback);
        session.AgentUpn = claims.Upn;
        session.AgentDisplayName = claims.DisplayName;
        session.PresentationStatus = "presentation_verified";

        if (string.IsNullOrWhiteSpace(session.AgentUpn))
        {
            FailSession(sessionId, "Agent UPN (revocationId) missing from credential.");
            return;
        }

        session.Status = VerificationStatuses.AgentVerified;
        session.AgentVerifiedAt = DateTimeOffset.UtcNow;
        session.Phase = VerificationPhases.User;
        _sessionService.SaveSession(session);
        _log.LogInformation("Agent verified for session {SessionId}", sessionId);
    }

    private async Task ProcessUserPresentationAsync(string sessionId, CallbackEvent callback)
    {
        var session = _sessionService.GetSession(sessionId);
        if (session == null || session.Status != VerificationStatuses.AgentVerified)
        {
            return;
        }

        var claims = ExtractClaims(callback);
        session.UserUpn = claims.Upn;
        session.UserDisplayName = claims.DisplayName;
        session.UserMail = claims.Mail;
        session.PresentationStatus = "presentation_verified";
        session.Status = VerificationStatuses.Complete;
        session.CompletedAt = DateTimeOffset.UtcNow;
        _sessionService.SaveSession(session);
        _auditService.TrackVerificationCompleted(session);
        _log.LogInformation("User verified for session {SessionId}", sessionId);
        await Task.CompletedTask;
    }

    private void FailSession(string sessionId, string reason)
    {
        var session = _sessionService.GetSession(sessionId);
        if (session == null)
        {
            return;
        }

        session.Status = VerificationStatuses.Failed;
        session.FailureReason = reason;
        session.CompletedAt = DateTimeOffset.UtcNow;
        _sessionService.SaveSession(session);
        _auditService.TrackVerificationFailed(session, reason);
    }

    private CredentialClaims ExtractClaims(CallbackEvent callback)
    {
        var credentialType = _configuration.GetValue("VerifiedID:CredentialType", "VerifiedEmployee");
        var upnClaimName = _configuration.GetValue("VerifiedID:UpnClaimName", "revocationId");
        var displayNameClaimName = _configuration.GetValue("VerifiedID:DisplayNameClaimName", "displayName");
        var mailClaimName = _configuration.GetValue("VerifiedID:EmailClaimName", "mail");

        foreach (var vc in callback.verifiedCredentialsData)
        {
            var typeMatches = vc.type?.Any(t => t.Contains(credentialType, StringComparison.OrdinalIgnoreCase)) == true;
            if (!typeMatches)
            {
                continue;
            }

            vc.claims ??= new Dictionary<string, string>();
            return new CredentialClaims
            {
                Upn = GetClaim(vc.claims, upnClaimName),
                DisplayName = GetClaim(vc.claims, displayNameClaimName),
                Mail = GetClaim(vc.claims, mailClaimName)
            };
        }

        return new CredentialClaims();
    }

    private static string? GetClaim(IDictionary<string, string> claims, string claimName) =>
        claims.TryGetValue(claimName, out var value) ? value : null;

    private sealed class CredentialClaims
    {
        public string? Upn { get; init; }
        public string? DisplayName { get; init; }
        public string? Mail { get; init; }
    }
}
