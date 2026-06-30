using System.Net.Http.Headers;
using System.Text;
using Azure.Identity;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace VerifiedHelpdesk.Services;

public class GraphAuthorizationService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<GraphAuthorizationService> _log;

    public GraphAuthorizationService(
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<GraphAuthorizationService> log)
    {
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
        _log = log;
    }

    public async Task<bool> IsHelpdeskMemberAsync(string agentUpn, CancellationToken cancellationToken = default)
    {
        var groupId = _configuration["AppSettings:ITHelpdeskGroupId"];
        if (string.IsNullOrWhiteSpace(groupId))
        {
            _log.LogWarning("AppSettings:ITHelpdeskGroupId is not configured.");
            return false;
        }

        var token = await GetGraphAccessTokenAsync(cancellationToken);
        if (string.IsNullOrEmpty(token))
        {
            return false;
        }

        var client = _httpClientFactory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var url = $"https://graph.microsoft.com/v1.0/users/{Uri.EscapeDataString(agentUpn)}/checkMemberGroups";
        var payload = JsonConvert.SerializeObject(new { groupIds = new[] { groupId } });
        using var content = new StringContent(payload, Encoding.UTF8, "application/json");
        var response = await client.PostAsync(url, content, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            _log.LogError("Graph checkMemberGroups failed for {AgentUpn}: {Status} {Body}", agentUpn, response.StatusCode, body);
            return false;
        }

        var result = JObject.Parse(body);
        var matchedGroups = result["value"]?.ToObject<List<string>>() ?? new List<string>();
        return matchedGroups.Contains(groupId);
    }

    private async Task<string?> GetGraphAccessTokenAsync(CancellationToken cancellationToken)
    {
        try
        {
            var credential = new ChainedTokenCredential(new ManagedIdentityCredential(), new EnvironmentCredential());
            var token = await credential.GetTokenAsync(
                new Azure.Core.TokenRequestContext(new[] { "https://graph.microsoft.com/.default" }),
                cancellationToken);
            return token.Token;
        }
        catch (Exception ex)
        {
            _log.LogError(ex, "Failed to acquire Graph access token.");
            return null;
        }
    }
}
