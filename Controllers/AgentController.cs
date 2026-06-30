using System.Diagnostics;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using VerifiedHelpdesk.Models;

namespace VerifiedHelpdesk.Controllers;

[Authorize]
public class AgentController : Controller
{
    private readonly IConfiguration _configuration;

    public AgentController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public IActionResult Index()
    {
        ViewData["Title"] = _configuration.GetValue("AppSettings:PortalTitle", "Verified Helpdesk");
        ViewData["AuthorizedAgentLabel"] = _configuration.GetValue("AppSettings:AuthorizedAgentLabel", "Verified Employee");
        return View();
    }

    [AllowAnonymous]
    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View("~/Views/Shared/Error.cshtml", new ErrorViewModel
        {
            RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
        });
    }
}
