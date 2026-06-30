using System.Net.Http.Headers;
using System.Text;
using Microsoft.AspNetCore.Http.Extensions;
using Newtonsoft.Json;
using VerifiedHelpdesk.Helpers;
using VerifiedHelpdesk.Models;

namespace VerifiedHelpdesk.Services;

public class VerifiedIdPresentationService
{
    private readonly IConfiguration _configuration;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<VerifiedIdPresentationService> _log;
    private readonly string _apiKey;

    public VerifiedIdPresentationService(
        IConfiguration configuration,
        IHttpClientFactory httpClientFactory,
        ILogger<VerifiedIdPresentationService> log)
    {
        _configuration = configuration;
        _httpClientFactory = httpClientFactory;
        _log = log;
        _apiKey = Environment.GetEnvironmentVariable("API-KEY") ?? string.Empty;
    }

    public PresentationRequest CreatePresentationRequest(string stateId, HttpRequest request)
    {
        var presentationRequest = new PresentationRequest
        {
            includeQRCode = _configuration.GetValue("VerifiedID:includeQRCode", false),
            authority = _configuration["VerifiedID:DidAuthority"],
            registration = new Registration
            {
                clientName = _configuration.GetValue("VerifiedID:client_name", "Helpdesk Verification"),
                purpose = _configuration.GetValue("VerifiedID:Purpose", "To prove your identity")
            },
            callback = new Callback
            {
                url = $"{GetRequestHostName(request)}/api/verifier/presentationcallback",
                state = stateId,
                headers = new Dictionary<string, string> { { "api-key", _apiKey } }
            },
            includeReceipt = _configuration.GetValue("VerifiedID:includeReceipt", false),
            requestedCredentials = new List<RequestedCredential>()
        };

        if (string.IsNullOrEmpty(presentationRequest.registration.purpose))
        {
            presentationRequest.registration.purpose = null;
        }

        var credentialType = _configuration.GetValue("VerifiedID:CredentialType", "VerifiedEmployee");
        var allowRevoked = _configuration.GetValue("VerifiedID:allowRevoked", false);
        var validateLinkedDomain = _configuration.GetValue("VerifiedID:validateLinkedDomain", true);
        var enableFaceCheck = _configuration.GetValue("VerifiedID:EnableFaceCheck", false);

        var validation = new Validation
        {
            allowRevoked = allowRevoked,
            validateLinkedDomain = validateLinkedDomain
        };

        if (enableFaceCheck)
        {
            validation.faceCheck = new FaceCheck
            {
                sourcePhotoClaimName = _configuration.GetValue("VerifiedID:sourcePhotoClaimName", "photo"),
                matchConfidenceThreshold = _configuration.GetValue("VerifiedID:matchConfidenceThreshold", 70)
            };
        }

        presentationRequest.requestedCredentials.Add(new RequestedCredential
        {
            type = credentialType,
            acceptedIssuers = new List<string>(),
            configuration = new Configuration { validation = validation }
        });

        return presentationRequest;
    }

    public async Task<(bool success, string content, string? error)> CreatePresentationRequestAsync(
        string stateId,
        HttpRequest request,
        CancellationToken cancellationToken = default)
    {
        var accessToken = await MsalAccessTokenHandler.GetAccessToken(_configuration);
        if (accessToken.Item1 == string.Empty)
        {
            _log.LogError("Failed to acquire access token: {Error} {Description}", accessToken.error, accessToken.error_description);
            return (false, string.Empty, accessToken.error_description);
        }

        var presentationRequest = CreatePresentationRequest(stateId, request);
        var jsonString = JsonConvert.SerializeObject(presentationRequest, Formatting.None, new JsonSerializerSettings
        {
            NullValueHandling = NullValueHandling.Ignore
        });

        var url = $"{_configuration["VerifiedID:ApiEndpoint"]}createPresentationRequest";
        var client = _httpClientFactory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.token);
        var response = await client.PostAsync(url, new StringContent(jsonString, Encoding.UTF8, "application/json"), cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);

        if (response.StatusCode != System.Net.HttpStatusCode.Created)
        {
            _log.LogError("Verified ID API error: {Body}", body);
            return (false, string.Empty, body);
        }

        return (true, body, null);
    }

    public static string GetRequestHostName(HttpRequest request)
    {
        const string scheme = "https";
        var originalHost = request.Headers["x-original-host"].ToString();
        return !string.IsNullOrEmpty(originalHost)
            ? $"{scheme}://{originalHost}"
            : $"{scheme}://{request.Host}";
    }
}
