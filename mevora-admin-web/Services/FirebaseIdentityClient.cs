using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Mevora.Admin.Web.Configuration;
using Microsoft.Extensions.Options;

namespace Mevora.Admin.Web.Services;

public sealed record FirebaseTokens(string IdToken, string RefreshToken, DateTimeOffset ExpiresAt, string Uid);

public sealed record MfaEnrollment(string EnrollmentId, string DisplayName, bool IsTotp);

/// <summary>Outcome of the first (password) factor.</summary>
public abstract record PasswordSignInResult
{
    public sealed record Success(FirebaseTokens Tokens) : PasswordSignInResult;
    public sealed record SecondFactorRequired(string PendingCredential, IReadOnlyList<MfaEnrollment> Enrollments) : PasswordSignInResult;
    public sealed record Failed(string Reason) : PasswordSignInResult;
}

public sealed record TotpEnrollmentStart(string SharedSecretKey, string SessionInfo, int PeriodSeconds, int CodeLength, string OtpAuthUri);

public interface IFirebaseIdentityClient
{
    Task<PasswordSignInResult> SignInWithPasswordAsync(string email, string password, CancellationToken ct);
    Task<FirebaseTokens?> FinalizeTotpSignInAsync(string pendingCredential, string enrollmentId, string code, CancellationToken ct);
    Task<TotpEnrollmentStart?> StartTotpEnrollmentAsync(string idToken, string accountLabel, CancellationToken ct);
    Task<FirebaseTokens?> FinalizeTotpEnrollmentAsync(string idToken, string sessionInfo, string code, CancellationToken ct);
    Task<FirebaseTokens?> RefreshAsync(string refreshToken, CancellationToken ct);

    /// <summary>
    /// Asks Firebase Authentication to email a password-setup (reset) link to
    /// a staff address. Firebase sends it; the link never reaches this server
    /// or the screen of whoever triggered it.
    /// </summary>
    Task<bool> SendPasswordSetupEmailAsync(string email, CancellationToken ct);
}

/// <summary>
/// Staff sign-in against Firebase Authentication / Identity Platform, done
/// entirely server-side over the documented REST API. The browser never runs
/// the Firebase SDK and never holds an ID or refresh token: it gets an
/// HttpOnly session cookie that points at a server-side session.
///
/// MFA is TOTP (Identity Platform). Enrolment and the second-factor step go
/// through mfaEnrollment:start/finalize and mfaSignIn:finalize.
/// </summary>
public sealed class FirebaseIdentityClient(HttpClient http, IOptions<AdminWebOptions> options, ILogger<FirebaseIdentityClient> logger)
    : IFirebaseIdentityClient
{
    private readonly AdminWebOptions _options = options.Value;

    private string IdentityBase => _options.UsesAuthEmulator
        ? $"http://{_options.AuthEmulatorHost}/identitytoolkit.googleapis.com"
        : "https://identitytoolkit.googleapis.com";

    private string SecureTokenBase => _options.UsesAuthEmulator
        ? $"http://{_options.AuthEmulatorHost}/securetoken.googleapis.com"
        : "https://securetoken.googleapis.com";

    private string Key => Uri.EscapeDataString(_options.WebApiKey);

    public async Task<PasswordSignInResult> SignInWithPasswordAsync(string email, string password, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            $"{IdentityBase}/v1/accounts:signInWithPassword?key={Key}",
            new {email, password, returnSecureToken = true},
            ct);
        var body = await ReadJson(response, ct);
        if (!response.IsSuccessStatusCode)
        {
            // One message for every credential failure: no account oracle.
            logger.LogInformation("staff_password_sign_in_failed status={Status}", (int)response.StatusCode);
            return new PasswordSignInResult.Failed("invalid_credentials");
        }
        if (body.TryGetProperty("mfaPendingCredential", out var pending))
        {
            var enrollments = new List<MfaEnrollment>();
            if (body.TryGetProperty("mfaInfo", out var info) && info.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in info.EnumerateArray())
                {
                    enrollments.Add(new MfaEnrollment(
                        e.TryGetProperty("mfaEnrollmentId", out var id) ? id.GetString() ?? "" : "",
                        e.TryGetProperty("displayName", out var dn) ? dn.GetString() ?? "Authenticator" : "Authenticator",
                        e.TryGetProperty("totpInfo", out _)));
                }
            }
            return new PasswordSignInResult.SecondFactorRequired(pending.GetString() ?? "", enrollments);
        }
        return new PasswordSignInResult.Success(TokensFrom(body, "idToken", "refreshToken", "expiresIn", "localId"));
    }

    public async Task<FirebaseTokens?> FinalizeTotpSignInAsync(string pendingCredential, string enrollmentId, string code, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            $"{IdentityBase}/v2/accounts/mfaSignIn:finalize?key={Key}",
            new {mfaPendingCredential = pendingCredential, mfaEnrollmentId = enrollmentId, totpVerificationInfo = new {verificationCode = code}},
            ct);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogInformation("staff_mfa_sign_in_failed status={Status}", (int)response.StatusCode);
            return null;
        }
        var body = await ReadJson(response, ct);
        return TokensFromIdToken(body);
    }

    public async Task<TotpEnrollmentStart?> StartTotpEnrollmentAsync(string idToken, string accountLabel, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            $"{IdentityBase}/v2/accounts/mfaEnrollment:start?key={Key}",
            new {idToken, totpEnrollmentInfo = new { }},
            ct);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogWarning("staff_totp_enrollment_start_failed status={Status}", (int)response.StatusCode);
            return null;
        }
        var body = await ReadJson(response, ct);
        if (!body.TryGetProperty("totpSessionInfo", out var session)) return null;
        var secret = session.GetProperty("sharedSecretKey").GetString() ?? "";
        var period = session.TryGetProperty("periodSec", out var p) && p.TryGetInt32(out var pv) ? pv : 30;
        var length = session.TryGetProperty("verificationCodeLength", out var l) && l.TryGetInt32(out var lv) ? lv : 6;
        var issuer = Uri.EscapeDataString("Mevora Admin");
        var label = Uri.EscapeDataString($"Mevora Admin:{accountLabel}");
        var uri = $"otpauth://totp/{label}?secret={secret}&issuer={issuer}&digits={length}&period={period}";
        return new TotpEnrollmentStart(secret, session.GetProperty("sessionInfo").GetString() ?? "", period, length, uri);
    }

    public async Task<FirebaseTokens?> FinalizeTotpEnrollmentAsync(string idToken, string sessionInfo, string code, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            $"{IdentityBase}/v2/accounts/mfaEnrollment:finalize?key={Key}",
            new {idToken, displayName = "Authenticator app", totpVerificationInfo = new {sessionInfo, verificationCode = code}},
            ct);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogInformation("staff_totp_enrollment_finalize_failed status={Status}", (int)response.StatusCode);
            return null;
        }
        return TokensFromIdToken(await ReadJson(response, ct));
    }

    public async Task<bool> SendPasswordSetupEmailAsync(string email, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync(
            $"{IdentityBase}/v1/accounts:sendOobCode?key={Key}",
            new {requestType = "PASSWORD_RESET", email},
            ct);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogWarning("staff_password_setup_email_failed status={Status}", (int)response.StatusCode);
            return false;
        }
        return true;
    }

    public async Task<FirebaseTokens?> RefreshAsync(string refreshToken, CancellationToken ct)
    {
        using var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "refresh_token",
            ["refresh_token"] = refreshToken,
        });
        using var response = await http.PostAsync($"{SecureTokenBase}/v1/token?key={Key}", content, ct);
        if (!response.IsSuccessStatusCode)
        {
            // Disabled user, revoked tokens, deleted account: the session ends.
            logger.LogInformation("staff_token_refresh_failed status={Status}", (int)response.StatusCode);
            return null;
        }
        var body = await ReadJson(response, ct);
        return TokensFrom(body, "id_token", "refresh_token", "expires_in", "user_id");
    }

    private static FirebaseTokens TokensFrom(JsonElement body, string idKey, string refreshKey, string expiresKey, string uidKey)
    {
        var expiresIn = body.TryGetProperty(expiresKey, out var e) && int.TryParse(e.GetString(), out var seconds) ? seconds : 3600;
        return new FirebaseTokens(
            body.GetProperty(idKey).GetString() ?? "",
            body.GetProperty(refreshKey).GetString() ?? "",
            DateTimeOffset.UtcNow.AddSeconds(expiresIn),
            body.TryGetProperty(uidKey, out var uid) ? uid.GetString() ?? "" : JwtSubject(body.GetProperty(idKey).GetString()));
    }

    private static FirebaseTokens TokensFromIdToken(JsonElement body)
    {
        var id = body.GetProperty("idToken").GetString() ?? "";
        return new FirebaseTokens(id, body.GetProperty("refreshToken").GetString() ?? "", JwtExpiry(id), JwtSubject(id));
    }

    private static async Task<JsonElement> ReadJson(HttpResponseMessage response, CancellationToken ct)
    {
        var text = await response.Content.ReadAsStringAsync(ct);
        if (string.IsNullOrWhiteSpace(text)) return default;
        try
        {
            return JsonDocument.Parse(text).RootElement.Clone();
        }
        catch (JsonException)
        {
            return default;
        }
    }

    /// <summary>Reads (never trusts) the payload of a token Firebase just issued to us.</summary>
    internal static JsonElement JwtPayload(string? jwt)
    {
        var parts = (jwt ?? "").Split('.');
        if (parts.Length < 2) return default;
        var payload = parts[1].Replace('-', '+').Replace('_', '/');
        payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
        try
        {
            return JsonDocument.Parse(Convert.FromBase64String(payload)).RootElement.Clone();
        }
        catch (Exception)
        {
            return default;
        }
    }

    private static string JwtSubject(string? jwt)
    {
        var payload = JwtPayload(jwt);
        return payload.ValueKind == JsonValueKind.Object && payload.TryGetProperty("sub", out var sub) ? sub.GetString() ?? "" : "";
    }

    private static DateTimeOffset JwtExpiry(string? jwt)
    {
        var payload = JwtPayload(jwt);
        return payload.ValueKind == JsonValueKind.Object && payload.TryGetProperty("exp", out var exp) && exp.TryGetInt64(out var s)
            ? DateTimeOffset.FromUnixTimeSeconds(s)
            : DateTimeOffset.UtcNow.AddMinutes(55);
    }
}
