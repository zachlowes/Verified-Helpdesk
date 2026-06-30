using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using VerifiedHelpdesk.Models;
using VerifiedHelpdesk.Services;

namespace VerifiedHelpdesk.Controllers;

[ApiController]
[AllowAnonymous]
public class SessionApiController : ControllerBase
{
    private readonly SessionService _sessionService;
    private readonly VerifiedIdPresentationService _presentationService;
    private readonly ILogger<SessionApiController> _log;

    public SessionApiController(
        SessionService sessionService,
        VerifiedIdPresentationService presentationService,
        ILogger<SessionApiController> log)
    {
        _sessionService = sessionService;
        _presentationService = presentationService;
        _log = log;
    }

    [Authorize]
    [HttpPost("/api/session/start")]
    public ActionResult StartSession()
    {
        var signedInUpn = User.Identity?.Name;
        var session = _sessionService.CreateSession(signedInUpn);
        _log.LogInformation("Started verification session {SessionId}", session.SessionId);
        return Ok(new { sessionId = session.SessionId, status = session.Status });
    }

    [HttpGet("/api/session/{sessionId}/status")]
    public ActionResult GetSessionStatus(string sessionId)
    {
        var session = _sessionService.GetSession(sessionId);
        if (session == null)
        {
            return NotFound(new { status = "not_found", message = "Session not found or expired." });
        }

        return Ok(new
        {
            sessionId = session.SessionId,
            status = session.Status,
            phase = session.Phase,
            agentDisplayName = session.AgentDisplayName,
            agentUpn = session.AgentUpn,
            userDisplayName = session.UserDisplayName,
            userUpn = session.UserUpn,
            userMail = session.UserMail,
            failureReason = session.FailureReason,
            callerUrl = Url.Action("Index", "Caller", new { sessionId }, Request.Scheme)
        });
    }

    [HttpGet("/api/verifier/presentation-request")]
    public async Task<ActionResult> PresentationRequest([FromQuery] string sessionId, [FromQuery] string phase = VerificationPhases.Agent)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            return BadRequest(new { error = "400", error_description = "Missing sessionId." });
        }

        var session = _sessionService.GetSession(sessionId);
        if (session == null)
        {
            return NotFound(new { error = "404", error_description = "Session not found or expired." });
        }

        if (phase == VerificationPhases.Agent && session.Status != VerificationStatuses.AwaitingAgent)
        {
            return BadRequest(new { error = "400", error_description = "Session is not awaiting agent verification." });
        }

        if (phase == VerificationPhases.User && session.Status != VerificationStatuses.AgentVerified)
        {
            return BadRequest(new { error = "400", error_description = "Session is not ready for user verification." });
        }

        var stateId = _sessionService.GetPresentationStateId(sessionId, phase);
        var result = await _presentationService.CreatePresentationRequestAsync(stateId, Request);
        if (!result.success)
        {
            return BadRequest(new { error = "400", error_description = result.error });
        }

        var requestConfig = JObject.Parse(result.content);
        requestConfig.Add(new JProperty("id", stateId));

        session.ActivePresentationState = stateId;
        session.Phase = phase;
        _sessionService.SaveSession(session);
        _sessionService.SetPresentationState(stateId, sessionId, phase, "request_created");

        return Content(JsonConvert.SerializeObject(requestConfig), "application/json");
    }
}
