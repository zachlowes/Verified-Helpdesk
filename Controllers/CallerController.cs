using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VerifiedHelpdesk.Models;
using VerifiedHelpdesk.Services;

namespace VerifiedHelpdesk.Controllers;

[AllowAnonymous]
public class CallerController : Controller
{
    private readonly SessionService _sessionService;
    private readonly IConfiguration _configuration;

    public CallerController(SessionService sessionService, IConfiguration configuration)
    {
        _sessionService = sessionService;
        _configuration = configuration;
    }

    [HttpGet("/caller/{sessionId}")]
    public IActionResult Index(string sessionId)
    {
        var session = _sessionService.GetSession(sessionId);
        if (session == null ||
            session.Status == VerificationStatuses.AwaitingAgent ||
            session.Status == VerificationStatuses.Failed)
        {
            ViewData["Title"] = _configuration.GetValue("AppSettings:PortalTitle", "Verified Helpdesk");
            ViewData["ErrorMessage"] = "This verification session is invalid or has expired.";
            return View("Invalid");
        }

        ViewData["Title"] = _configuration.GetValue("AppSettings:PortalTitle", "Verified Helpdesk");
        ViewData["AuthorizedAgentLabel"] = _configuration.GetValue("AppSettings:AuthorizedAgentLabel", "Verified Employee");
        ViewData["SessionId"] = sessionId;
        ViewData["AgentDisplayName"] = session.AgentDisplayName;
        return View(session);
    }
}
