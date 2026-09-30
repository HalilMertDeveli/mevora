using System.Globalization;
using System.Security.Claims;
using System.Threading.RateLimiting;
using Mevora.Admin.Web.Configuration;
using Mevora.Admin.Web.Pages;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);
var isDevelopment = builder.Environment.IsDevelopment();

builder.Services.AddOptions<AdminWebOptions>()
    .Bind(builder.Configuration.GetSection(AdminWebOptions.Section))
    .Validate(o => !o.Validate(isDevelopment).Any(), "Invalid AdminWeb configuration")
    .ValidateOnStart();

builder.Services.AddHttpContextAccessor();
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSingleton<DistributedTicketStore>();
builder.Services.AddSingleton<LoginFlowStore>();
builder.Services.AddScoped<IStaffSession, StaffSession>();
builder.Services.AddHttpClient<IFirebaseIdentityClient, FirebaseIdentityClient>(c => c.Timeout = TimeSpan.FromSeconds(15));
builder.Services.AddHttpClient<IAdminApiClient, AdminApiClient>(c => c.Timeout = TimeSpan.FromSeconds(60));

builder.Services
    .AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie();
builder.Services.AddOptions<CookieAuthenticationOptions>(CookieAuthenticationDefaults.AuthenticationScheme)
    .Configure<DistributedTicketStore, IOptions<AdminWebOptions>>((cookie, store, admin) =>
    {
        // __Host- binds the cookie to this exact origin over HTTPS. Plain HTTP
        // on localhost (emulator QA) cannot carry it, so Development uses a
        // plain name.
        cookie.Cookie.Name = isDevelopment ? "mevora-admin" : "__Host-mevora-admin";
        cookie.Cookie.HttpOnly = true;
        cookie.Cookie.SameSite = SameSiteMode.Strict;
        cookie.Cookie.SecurePolicy = isDevelopment ? CookieSecurePolicy.SameAsRequest : CookieSecurePolicy.Always;
        cookie.Cookie.Path = "/";
        cookie.LoginPath = "/Login";
        cookie.LogoutPath = "/Logout";
        cookie.AccessDeniedPath = "/Status/403";
        cookie.ExpireTimeSpan = TimeSpan.FromMinutes(admin.Value.SessionIdleMinutes);
        cookie.SlidingExpiration = true;
        cookie.SessionStore = store;
        cookie.Events.OnValidatePrincipal = context =>
        {
            // Absolute lifetime, independent of activity.
            var started = context.Principal?.FindFirst(StaffClaims.SessionStarted)?.Value;
            if (!long.TryParse(started, NumberStyles.Integer, CultureInfo.InvariantCulture, out var seconds) ||
                DateTimeOffset.UtcNow - DateTimeOffset.FromUnixTimeSeconds(seconds) > TimeSpan.FromHours(admin.Value.SessionAbsoluteHours))
            {
                context.RejectPrincipal();
                return context.HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            }
            return Task.CompletedTask;
        };
        cookie.Events.OnRedirectToAccessDenied = context =>
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return Task.CompletedTask;
        };
    });

builder.Services.AddSingleton<IAuthorizationPolicyProvider, PermissionPolicyProvider>();
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build();
});

builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = isDevelopment ? "mevora-admin-af" : "__Host-mevora-admin-af";
    options.Cookie.SameSite = SameSiteMode.Strict;
    options.Cookie.SecurePolicy = isDevelopment ? CookieSecurePolicy.SameAsRequest : CookieSecurePolicy.Always;
    options.Cookie.HttpOnly = true;
    options.HeaderName = "X-CSRF-TOKEN";
});

builder.Services.AddRazorPages(options =>
{
    options.Conventions.AuthorizeFolder("/");
    options.Conventions.AllowAnonymousToPage("/Login");
    options.Conventions.AllowAnonymousToPage("/Status");
    options.Conventions.AllowAnonymousToPage("/Error");
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    static string Partition(HttpContext http) =>
        http.User.FindFirstValue(StaffClaims.Uid) ?? http.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    // Everyone: a generous ceiling that only a script would hit.
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(http =>
        RateLimitPartition.GetFixedWindowLimiter(Partition(http), _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 300,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        }));
    // Sign-in attempts (password / code submissions) per client address.
    // Rendering the form is not an attempt and is not counted.
    options.AddPolicy("login", http => HttpMethods.IsGet(http.Request.Method)
        ? RateLimitPartition.GetNoLimiter("login-form")
        : RateLimitPartition.GetFixedWindowLimiter(
            http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions {PermitLimit = 20, Window = TimeSpan.FromMinutes(10), QueueLimit = 0}));
    // User search is the obvious enumeration target.
    options.AddPolicy("search", http => RateLimitPartition.GetFixedWindowLimiter(
        Partition(http),
        _ => new FixedWindowRateLimiterOptions {PermitLimit = 30, Window = TimeSpan.FromMinutes(1), QueueLimit = 0}));
});

builder.Services.AddHsts(options =>
{
    options.MaxAge = TimeSpan.FromDays(365);
    options.IncludeSubDomains = true;
    options.Preload = false;
});

var app = builder.Build();

if (!isDevelopment)
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
    app.UseHttpsRedirection();
}

app.UseMiddleware<SecurityHeadersMiddleware>();
app.UseStatusCodePagesWithReExecute("/Status/{0}");
app.UseStaticFiles();
app.UseRouting();
app.UseRateLimiter();
app.UseAuthentication();

// The backend said the staff session is over (revoked, disabled, expired):
// end it here too and send the staff member back to sign in.
app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (SessionEndedException)
    {
        await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        context.Response.Redirect("/Login?reason=expired");
    }
});

app.UseAuthorization();

app.MapGet("/healthz", () => Results.Text("ok")).AllowAnonymous();
app.MapRazorPages();

app.Run();

public partial class Program;
