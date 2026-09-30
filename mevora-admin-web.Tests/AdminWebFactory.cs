using System.Collections.Concurrent;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Mevora.Admin.Web.Tests;

/// <summary>Records every admin command the pages send, and answers from a script.</summary>
public sealed class FakeAdminApi : IAdminApiClient
{
    public ConcurrentQueue<(string Command, JsonElement Payload)> Calls { get; } = new();
    public Dictionary<string, Func<JsonElement, JsonElement>> Responses { get; } = new();
    public Dictionary<string, string> Failures { get; } = new();

    public Task<JsonElement> CallAsync(string command, object? payload = null, CancellationToken ct = default) =>
        CallWithTokenAsync("test-id-token", command, payload, ct);

    public Task<JsonElement> CallWithTokenAsync(string idToken, string command, object? payload = null, CancellationToken ct = default)
    {
        var json = JsonSerializer.SerializeToElement(payload ?? new { }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Calls.Enqueue((command, json));
        if (Failures.TryGetValue(command, out var code))
        {
            throw new AdminApiException(code, "req-test-1234567890");
        }
        return Task.FromResult(Responses.TryGetValue(command, out var respond)
            ? respond(json)
            : JsonDocument.Parse("""{"items":[],"nextCursor":null}""").RootElement.Clone());
    }

    public bool Called(string command) => Calls.Any(c => c.Command == command);
    public JsonElement Last(string command) => Calls.Last(c => c.Command == command).Payload;
}

public sealed class FakeIdentity : IFirebaseIdentityClient
{
    public PasswordSignInResult Next { get; set; } = new PasswordSignInResult.Failed("invalid_credentials");

    public Task<PasswordSignInResult> SignInWithPasswordAsync(string email, string password, CancellationToken ct) => Task.FromResult(Next);

    public Task<FirebaseTokens?> FinalizeTotpSignInAsync(string pendingCredential, string enrollmentId, string code, CancellationToken ct) =>
        Task.FromResult<FirebaseTokens?>(code == "123456" ? Tokens() : null);

    public Task<TotpEnrollmentStart?> StartTotpEnrollmentAsync(string idToken, string accountLabel, CancellationToken ct) =>
        Task.FromResult<TotpEnrollmentStart?>(new TotpEnrollmentStart("JBSWY3DPEHPK3PXP", "session-info", 30, 6, "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP"));

    public Task<FirebaseTokens?> FinalizeTotpEnrollmentAsync(string idToken, string sessionInfo, string code, CancellationToken ct) =>
        Task.FromResult<FirebaseTokens?>(code == "654321" ? Tokens() : null);

    public Task<FirebaseTokens?> RefreshAsync(string refreshToken, CancellationToken ct) => Task.FromResult<FirebaseTokens?>(Tokens());

    public static FirebaseTokens Tokens() => new("header.payload.sig", "refresh-token", DateTimeOffset.UtcNow.AddHours(1), "staff-1");
}

/// <summary>
/// Signs a test request in as a staff member described by the
/// "X-Test-Staff: uid|role|perm,perm" header; no header = anonymous.
/// </summary>
public sealed class TestStaffHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string Scheme = "TestStaff";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("X-Test-Staff", out var header))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }
        var parts = header.ToString().Split('|');
        var claims = new List<Claim>
        {
            new(StaffClaims.Uid, parts[0]),
            new(ClaimTypes.Name, parts[0]),
            new(StaffClaims.Role, parts[1]),
            new(StaffClaims.Mfa, "true"),
        };
        claims.AddRange(parts[2].Split(',', StringSplitOptions.RemoveEmptyEntries).Select(p => new Claim(StaffClaims.Permission, p)));
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme, ClaimTypes.Name, StaffClaims.Role));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme)));
    }
}

public sealed class AdminWebFactory : WebApplicationFactory<Program>
{
    public FakeAdminApi Api { get; } = new();
    public FakeIdentity Identity { get; } = new();
    public bool UseTestStaff { get; init; } = true;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("AdminWeb:BffSharedSecret", Secret);
        builder.ConfigureTestServices(services =>
        {
            services.AddSingleton<IAdminApiClient>(Api);
            services.AddSingleton<IFirebaseIdentityClient>(Identity);
            if (UseTestStaff)
            {
                services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, TestStaffHandler>(TestStaffHandler.Scheme, _ => { });
                services.PostConfigure<AuthenticationOptions>(o =>
                {
                    o.DefaultAuthenticateScheme = TestStaffHandler.Scheme;
                    o.DefaultChallengeScheme = CookieAuthenticationDefaults.AuthenticationScheme;
                    o.DefaultForbidScheme = CookieAuthenticationDefaults.AuthenticationScheme;
                });
            }
        });
    }

    /// <summary>A distinctive secret value so a leak into any page is detectable.</summary>
    public const string Secret = "test-bff-secret-DO-NOT-RENDER-7f3a9c";

    public HttpClient Client(string? staff = null)
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions {AllowAutoRedirect = false});
        if (staff is not null) client.DefaultRequestHeaders.Add("X-Test-Staff", staff);
        return client;
    }

    public static readonly string Moderator = "mod-1|moderator|dashboard.read,user.read,user.warn,user.suspend,case.read,case.assign,case.resolve,case.escalate,case.note,report.read,report.resolve,photo.read,photo.approve,photo.reject,photo.escalate";
    public static readonly string Senior = Moderator.Replace("mod-1|moderator|", "senior-1|senior_moderator|") + ",user.ban,user.restore,appeal.read,appeal.resolve";
    public static readonly string SupportAgent = "support-1|support_agent|dashboard.read,user.read,support.read,support.reply,support.assign,support.resolve";

    /// <summary>GETs a page and returns the antiforgery token rendered in its first form.</summary>
    public static async Task<string> AntiforgeryToken(HttpClient client, string path)
    {
        var html = await client.GetStringAsync(path);
        var match = Regex.Match(html, "name=\"__RequestVerificationToken\" type=\"hidden\" value=\"([^\"]+)\"");
        if (!match.Success)
        {
            match = Regex.Match(html, "value=\"([^\"]+)\" name=\"__RequestVerificationToken\"");
        }
        Assert.True(match.Success, "no antiforgery token on " + path);
        return match.Groups[1].Value;
    }

    public static JsonElement Json(string json) => JsonDocument.Parse(json).RootElement.Clone();
}
