using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using VerifiedHelpdesk.Models;
using VerifiedHelpdesk.Services;

namespace VerifiedHelpdesk.Controllers;

[Route("api/[action]")]
[ApiController]
public class CallbackController : Controller
{
    private readonly ILogger<CallbackController> _log;
    private readonly string _apiKey;
    private readonly IConfiguration _configuration;
    private readonly VerificationCallbackService _verificationCallbackService;
    private readonly SessionService _sessionService;

    public CallbackController(
        IConfiguration configuration,
        ILogger<CallbackController> log,
        VerificationCallbackService verificationCallbackService,
        SessionService sessionService)
    {
        _configuration = configuration;
        _log = log;
        _apiKey = Environment.GetEnvironmentVariable("API-KEY") ?? string.Empty;
        _verificationCallbackService = verificationCallbackService;
        _sessionService = sessionService;
    }

    [AllowAnonymous]
    [HttpPost("/api/verifier/presentationcallback")]
    public async Task<ActionResult> PresentationCallback()
    {
        _log.LogTrace("Presentation callback received.");
        return await HandlePresentationCallbackAsync();
    }

    [AllowAnonymous]
    [HttpGet("/api/request-status")]
    public ActionResult RequestStatus()
    {
        var state = Request.Query["id"].ToString();
        if (string.IsNullOrEmpty(state))
        {
            return BadRequest(new { error = "400", error_description = "Missing argument 'id'" });
        }

        var presentation = _sessionService.GetPresentationState(state);
        if (presentation == null)
        {
            return BadRequest(new { status = "request_not_created", message = "No data" });
        }

        var result = presentation.Status switch
        {
            "request_created" => new { status = presentation.Status, message = "Waiting to scan QR code" },
            "request_retrieved" => new { status = presentation.Status, message = "QR code scanned. Waiting for user action..." },
            "presentation_error" => BuildErrorResult(presentation),
            "presentation_verified" => BuildVerifiedResult(presentation),
            _ => new { status = "error", message = $"Invalid requestStatus '{presentation.Status}'" }
        };

        return Content(JsonConvert.SerializeObject(result), "application/json");
    }

    private object BuildErrorResult(PresentationCacheEntry presentation)
    {
        if (string.IsNullOrEmpty(presentation.CallbackBody))
        {
            return new { status = presentation.Status, message = "Presentation failed." };
        }

        var callback = JsonConvert.DeserializeObject<CallbackEvent>(presentation.CallbackBody);
        return new { status = presentation.Status, message = "Presentation failed: " + callback?.error?.message };
    }

    private object BuildVerifiedResult(PresentationCacheEntry presentation)
    {
        if (string.IsNullOrEmpty(presentation.CallbackBody))
        {
            return new { status = presentation.Status, message = "Presentation verified" };
        }

        var callback = JsonConvert.DeserializeObject<CallbackEvent>(presentation.CallbackBody);
        if (callback?.verifiedCredentialsData == null || callback.verifiedCredentialsData.Length == 0)
        {
            return new { status = presentation.Status, message = "Presentation verified" };
        }

        return new
        {
            status = presentation.Status,
            message = "Presentation verified",
            type = callback.verifiedCredentialsData[0].type,
            claims = callback.verifiedCredentialsData[0].claims,
            subject = callback.subject
        };
    }

    private async Task<ActionResult> HandlePresentationCallbackAsync()
    {
        try
        {
            Request.Headers.TryGetValue("api-key", out var apiKey);
            if (_apiKey != apiKey)
            {
                _log.LogTrace("api-key wrong or missing");
                return Unauthorized("api-key wrong or missing");
            }

            var body = await new StreamReader(Request.Body).ReadToEndAsync();
            _log.LogTrace(body);

            var callback = JsonConvert.DeserializeObject<CallbackEvent>(body);
            if (callback == null || string.IsNullOrEmpty(callback.state))
            {
                return BadRequest(new { error = "400", error_description = "Invalid callback payload." });
            }

            var validStatuses = new[] { "request_retrieved", "presentation_verified", "presentation_error" };
            if (!validStatuses.Contains(callback.requestStatus))
            {
                return BadRequest(new { error = "400", error_description = $"Unknown request status '{callback.requestStatus}'" });
            }

            var presentation = _sessionService.GetPresentationState(callback.state);
            if (presentation == null)
            {
                return BadRequest(new { error = "400", error_description = $"Invalid state '{callback.state}'" });
            }

            _sessionService.SetPresentationState(callback.state, presentation.SessionId, presentation.Phase, callback.requestStatus, body);
            await _verificationCallbackService.ProcessPresentationCallbackAsync(callback.state, body, callback.requestStatus);

            return Ok();
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = "400", error_description = ex.Message });
        }
    }
}
