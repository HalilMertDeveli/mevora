using System.Globalization;
using System.Security.Claims;
using System.Text.Json;
using Mevora.Admin.Web.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Mevora.Admin.Web.Services;

public interface IStaffSession
{
    /// <summary>A valid ID token for the signed-in staff member, refreshed when close to expiry; null when the session is over.</summary>
    Task<string?> GetIdTokenAsync(CancellationToken ct);

    Task SignInAsync(FirebaseTokens tokens, JsonElement staffProfile);

    Task SignOutAsync();
}

/// <summary>
/// The staff session. Tokens live inside the server-side authentication ticket
/// (see DistributedTicketStore); the browser's cookie only names the ticket.
/// </summary>
public sealed class StaffSession(
    IHttpContextAccessor accessor,
    IFirebaseIdentityClient identity,
    ILogger<StaffSession> logger) : IStaffSession
{
    public const string Scheme = CookieAuthenticationDefaults.AuthenticationScheme;
    private static readonly TimeSpan RefreshWindow = TimeSpan.FromMinutes(5);

    private HttpContext Http => accessor.HttpContext ?? throw new InvalidOperationException("No HTTP context.");

    public async Task<string?> GetIdTokenAsync(CancellationToken ct)
    {
        var result = await Http.AuthenticateAsync(Scheme);
        if (!result.Succeeded || result.Properties is null) return null;
        var props = result.Properties;
        var idToken = props.GetTokenValue("id_token");
        var refreshToken = props.GetTokenValue("refresh_token");
        var expiresAt = DateTimeOffset.TryParse(props.GetTokenValue("expires_at"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var e)
            ? e
            : DateTimeOffset.MinValue;
        if (idToken is not null && expiresAt - DateTimeOffset.UtcNow > RefreshWindow) return idToken;
        if (refreshToken is null) return null;

        var refreshed = await identity.RefreshAsync(refreshToken, ct);
        if (refreshed is null)
        {
            logger.LogInformation("staff_session_refresh_refused");
            await SignOutAsync();
            return null;
        }
        StoreTokens(props, refreshed);
        await Http.SignInAsync(Scheme, result.Principal!, props);
        return refreshed.IdToken;
    }

    public async Task SignInAsync(FirebaseTokens tokens, JsonElement profile)
    {
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, tokens.Uid),
            new(StaffClaims.Uid, tokens.Uid),
            new(ClaimTypes.Name, profile.Str("displayName") ?? tokens.Uid),
            new(StaffClaims.Role, profile.Str("role") ?? ""),
            new(StaffClaims.Mfa, profile.Bool("mfa") ? "true" : "false"),
            new(StaffClaims.Owner, profile.Bool("isOwner") ? "true" : "false"),
            new(StaffClaims.SessionStarted, DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)),
        };
        foreach (var permission in profile.Arr("permissions"))
        {
            if (permission.GetString() is { Length: > 0 } p) claims.Add(new Claim(StaffClaims.Permission, p));
        }
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme, ClaimTypes.Name, StaffClaims.Role));
        var props = new AuthenticationProperties {IsPersistent = false, AllowRefresh = true};
        StoreTokens(props, tokens);
        await Http.SignInAsync(Scheme, principal, props);
    }

    public Task SignOutAsync() => Http.SignOutAsync(Scheme);

    private static void StoreTokens(AuthenticationProperties props, FirebaseTokens tokens)
    {
        props.StoreTokens(
        [
            new AuthenticationToken {Name = "id_token", Value = tokens.IdToken},
            new AuthenticationToken {Name = "refresh_token", Value = tokens.RefreshToken},
            new AuthenticationToken {Name = "expires_at", Value = tokens.ExpiresAt.ToString("o", CultureInfo.InvariantCulture)},
        ]);
    }
}
