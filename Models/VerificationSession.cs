namespace VerifiedHelpdesk.Models;

public static class VerificationPhases
{
    public const string Agent = "agent";
    public const string User = "user";
}

public static class VerificationStatuses
{
    public const string AwaitingAgent = "awaiting_agent";
    public const string AgentVerified = "agent_verified";
    public const string Complete = "complete";
    public const string Failed = "failed";
}

public class VerificationSession
{
    public string SessionId { get; set; } = string.Empty;
    public string Phase { get; set; } = VerificationPhases.Agent;
    public string? AgentUpn { get; set; }
    public string? AgentDisplayName { get; set; }
    public string? UserUpn { get; set; }
    public string? UserDisplayName { get; set; }
    public string? UserMail { get; set; }
    public string Status { get; set; } = VerificationStatuses.AwaitingAgent;
    public string? SignedInAgentUpn { get; set; }
    public string? FailureReason { get; set; }
    public DateTimeOffset InitiatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? AgentVerifiedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string? ActivePresentationState { get; set; }
    public string? PresentationStatus { get; set; }
}
