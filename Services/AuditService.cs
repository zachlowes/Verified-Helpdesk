using Microsoft.ApplicationInsights;
using VerifiedHelpdesk.Models;

namespace VerifiedHelpdesk.Services;

public class AuditService
{
    private readonly TelemetryClient _telemetry;

    public AuditService(TelemetryClient telemetry)
    {
        _telemetry = telemetry;
    }

    public void TrackVerificationCompleted(VerificationSession session)
    {
        _telemetry.TrackEvent("VerificationCompleted", new Dictionary<string, string>
        {
            ["sessionId"] = session.SessionId,
            ["agentUpn"] = session.AgentUpn ?? string.Empty,
            ["agentDisplayName"] = session.AgentDisplayName ?? string.Empty,
            ["userUpn"] = session.UserUpn ?? string.Empty,
            ["userDisplayName"] = session.UserDisplayName ?? string.Empty,
            ["userMail"] = session.UserMail ?? string.Empty,
            ["result"] = session.Status,
            ["initiatedAt"] = session.InitiatedAt.ToString("O"),
            ["agentVerifiedAt"] = session.AgentVerifiedAt?.ToString("O") ?? string.Empty,
            ["completedAt"] = session.CompletedAt?.ToString("O") ?? string.Empty
        });
    }

    public void TrackVerificationFailed(VerificationSession session, string reason)
    {
        _telemetry.TrackEvent("VerificationFailed", new Dictionary<string, string>
        {
            ["sessionId"] = session.SessionId,
            ["agentUpn"] = session.AgentUpn ?? string.Empty,
            ["phase"] = session.Phase,
            ["result"] = session.Status,
            ["reason"] = reason,
            ["initiatedAt"] = session.InitiatedAt.ToString("O")
        });
    }
}
