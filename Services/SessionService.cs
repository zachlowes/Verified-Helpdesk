using Microsoft.Extensions.Caching.Memory;
using VerifiedHelpdesk.Models;

namespace VerifiedHelpdesk.Services;

public class SessionService
{
    private readonly IMemoryCache _cache;
    private readonly IConfiguration _configuration;

    public SessionService(IMemoryCache cache, IConfiguration configuration)
    {
        _cache = cache;
        _configuration = configuration;
    }

    private TimeSpan CacheDuration =>
        TimeSpan.FromSeconds(_configuration.GetValue("AppSettings:CacheExpiresInSeconds", 300));

    private static string SessionKey(string sessionId) => $"session:{sessionId}";

    private static string PresentationKey(string state) => $"presentation:{state}";

    public VerificationSession CreateSession(string? signedInAgentUpn)
    {
        var session = new VerificationSession
        {
            SessionId = Guid.NewGuid().ToString(),
            SignedInAgentUpn = signedInAgentUpn,
            Status = VerificationStatuses.AwaitingAgent,
            Phase = VerificationPhases.Agent,
            InitiatedAt = DateTimeOffset.UtcNow
        };
        SaveSession(session);
        return session;
    }

    public VerificationSession? GetSession(string sessionId)
    {
        return _cache.TryGetValue(SessionKey(sessionId), out VerificationSession? session) ? session : null;
    }

    public void SaveSession(VerificationSession session)
    {
        _cache.Set(SessionKey(session.SessionId), session, DateTimeOffset.UtcNow.Add(CacheDuration));
    }

    public void SetPresentationState(string state, string sessionId, string phase, string status, string? callbackBody = null)
    {
        var entry = new PresentationCacheEntry
        {
            SessionId = sessionId,
            Phase = phase,
            Status = status,
            CallbackBody = callbackBody
        };
        _cache.Set(PresentationKey(state), entry, DateTimeOffset.UtcNow.Add(CacheDuration));
    }

    public PresentationCacheEntry? GetPresentationState(string state)
    {
        return _cache.TryGetValue(PresentationKey(state), out PresentationCacheEntry? entry) ? entry : null;
    }

    public string GetPresentationStateId(string sessionId, string phase) =>
        phase == VerificationPhases.User ? $"{sessionId}-user" : sessionId;
}

public class PresentationCacheEntry
{
    public string SessionId { get; set; } = string.Empty;
    public string Phase { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? CallbackBody { get; set; }
}
