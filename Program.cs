using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using VerifiedHelpdesk.Services;

namespace VerifiedHelpdesk;

public class Program
{
    public static void Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        builder.Services.AddApplicationInsightsTelemetry();
        builder.Services.AddMemoryCache();
        builder.Services.AddHttpClient();

        builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
            .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"));

        builder.Services.AddControllersWithViews(options =>
        {
            var policy = new AuthorizationPolicyBuilder()
                .RequireAuthenticatedUser()
                .Build();
            options.Filters.Add(new AuthorizeFilter(policy));
        });

        builder.Services.AddRazorPages()
            .AddMicrosoftIdentityUI();

        builder.Services.AddScoped<SessionService>();
        builder.Services.AddScoped<GraphAuthorizationService>();
        builder.Services.AddScoped<AuditService>();
        builder.Services.AddScoped<VerifiedIdPresentationService>();
        builder.Services.AddScoped<VerificationCallbackService>();

        builder.Services.AddSession(options =>
        {
            options.IdleTimeout = TimeSpan.FromMinutes(30);
            options.Cookie.IsEssential = true;
            options.Cookie.HttpOnly = true;
        });

        var app = builder.Build();

        app.UseForwardedHeaders(new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost
        });

        if (!app.Environment.IsDevelopment())
        {
            app.UseExceptionHandler("/Agent/Error");
            app.UseHsts();
        }

        app.UseHttpsRedirection();
        app.UseStaticFiles();
        app.UseRouting();
        app.UseSession();
        app.UseAuthentication();
        app.UseAuthorization();

        app.MapControllerRoute(
            name: "caller",
            pattern: "caller/{sessionId}",
            defaults: new { controller = "Caller", action = "Index" });

        app.MapControllerRoute(
            name: "default",
            pattern: "{controller=Agent}/{action=Index}/{id?}");

        app.MapRazorPages();

        Environment.SetEnvironmentVariable("API-KEY", Guid.NewGuid().ToString());

        app.Run();
    }
}
