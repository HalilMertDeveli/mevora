using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;

namespace Mevora.Admin.Web.Services;

/// <summary>State carried between the steps of one sign-in (password → second factor / enrolment).</summary>
public sealed class LoginFlowState
{
    public string Stage { get; set; } = "password";
    public string Email { get; set; } = "";
    public string? PendingCredential { get; set; }
    public string? EnrollmentId { get; set; }
    public string? IdToken { get; set; }
    public string? RefreshToken { get; set; }
    public string? Uid { get; set; }
    public DateTimeOffset TokenExpiresAt { get; set; }
    public string? EnrollmentSession { get; set; }
    public string? EnrollmentSecret { get; set; }
    public string? EnrollmentUri { get; set; }
    public int Attempts { get; set; }
}

/// <summary>
/// Keeps in-progress sign-in state on the server for five minutes. The
/// browser holds only a random key in an HttpOnly cookie; the pending MFA
/// credential and any interim token never reach the page.
/// </summary>
public sealed class LoginFlowStore(IDistributedCache cache, IWebHostEnvironment env)
{
    public const string CookieName = "mevora-admin-login";
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(5);
    private const int MaxAttempts = 5;

    public async Task<LoginFlowState?> ReadAsync(HttpContext http)
    {
        if (!http.Request.Cookies.TryGetValue(CookieName, out var key) || key.Length != 43) return null;
        var bytes = await cache.GetAsync("mevora-admin-login:" + key);
        return bytes is null ? null : JsonSerializer.Deserialize<LoginFlowState>(bytes);
    }

    public async Task WriteAsync(HttpContext http, LoginFlowState state)
    {
        if (!http.Request.Cookies.TryGetValue(CookieName, out var key) || key.Length != 43)
        {
            key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        }
        await cache.SetAsync("mevora-admin-login:" + key, JsonSerializer.SerializeToUtf8Bytes(state),
            new DistributedCacheEntryOptions {AbsoluteExpirationRelativeToNow = Lifetime});
        http.Response.Cookies.Append(CookieName, key, new CookieOptions
        {
            HttpOnly = true,
            Secure = !env.IsDevelopment() || http.Request.IsHttps,
            SameSite = SameSiteMode.Strict,
            MaxAge = Lifetime,
            Path = "/Login",
        });
    }

    /// <summary>Counts a failed code; returns false once the flow is exhausted.</summary>
    public async Task<bool> RecordFailureAsync(HttpContext http, LoginFlowState state)
    {
        state.Attempts += 1;
        if (state.Attempts >= MaxAttempts)
        {
            await ClearAsync(http);
            return false;
        }
        await WriteAsync(http, state);
        return true;
    }

    public async Task ClearAsync(HttpContext http)
    {
        if (http.Request.Cookies.TryGetValue(CookieName, out var key))
        {
            await cache.RemoveAsync("mevora-admin-login:" + key);
        }
        http.Response.Cookies.Delete(CookieName, new CookieOptions {Path = "/Login"});
    }
}
