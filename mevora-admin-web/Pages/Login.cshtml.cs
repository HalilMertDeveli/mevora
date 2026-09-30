using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;

namespace Mevora.Admin.Web.Pages;

/// <summary>
/// Staff sign-in, server-side end to end:
///
///   password  → Firebase signInWithPassword
///   code      → TOTP second factor (mfaSignIn:finalize), when enrolled
///   enroll    → first-time TOTP enrolment, when the backend says MFA is
///               required and the account has none yet
///   admit     → adminRecordLogin: the backend checks adminStaff, MFA and
///               role, writes ADMIN_LOGIN to the audit log, and returns the
///               staff profile the session is built from
///
/// An ordinary member account, a disabled staff member or a missing second
/// factor never gets a session: admission is the backend's decision.
/// </summary>
[EnableRateLimiting("login")]
public sealed class LoginModel(
    IFirebaseIdentityClient identity,
    IAdminApiClient api,
    IStaffSession session,
    LoginFlowStore flow,
    ILogger<LoginModel> logger) : PageModel
{
    public string Stage { get; private set; } = "password";
    public string? Error { get; private set; }
    public string? Notice { get; private set; }
    public string? EnrollmentSecret { get; private set; }
    public string? EnrollmentUri { get; private set; }

    [BindProperty, EmailAddress, StringLength(254)] public string? Email { get; set; }
    [BindProperty, StringLength(200)] public string? Password { get; set; }
    [BindProperty, StringLength(10)] public string? Code { get; set; }

    public async Task<IActionResult> OnGetAsync(string? reason)
    {
        if (User.Identity?.IsAuthenticated == true) return Redirect("/Dashboard");
        if (reason == "expired") Notice = "Your session ended. Please sign in again.";
        var state = await flow.ReadAsync(HttpContext);
        if (state is not null)
        {
            Stage = state.Stage;
            EnrollmentSecret = state.EnrollmentSecret;
            EnrollmentUri = state.EnrollmentUri;
        }
        return Page();
    }

    public async Task<IActionResult> OnPostPasswordAsync()
    {
        await flow.ClearAsync(HttpContext);
        if (!ModelState.IsValid || string.IsNullOrWhiteSpace(Email) || string.IsNullOrEmpty(Password))
        {
            Error = "Enter your staff email and password.";
            return Page();
        }
        var email = Email.Trim().ToLowerInvariant();
        var result = await identity.SignInWithPasswordAsync(email, Password, HttpContext.RequestAborted);
        switch (result)
        {
        case PasswordSignInResult.Failed:
            Error = "Those details did not work.";
            return Page();
        case PasswordSignInResult.SecondFactorRequired mfa:
            var totp = mfa.Enrollments.FirstOrDefault(e => e.IsTotp) ?? mfa.Enrollments.FirstOrDefault();
            if (totp is null)
            {
                Error = "This account's second factor is not supported here. Contact a super admin.";
                return Page();
            }
            await flow.WriteAsync(HttpContext, new LoginFlowState
            {
                Stage = "code",
                Email = email,
                PendingCredential = mfa.PendingCredential,
                EnrollmentId = totp.EnrollmentId,
            });
            return RedirectToPage();
        case PasswordSignInResult.Success ok:
            return await AdmitAsync(ok.Tokens, email);
        default:
            Error = "Sign-in failed.";
            return Page();
        }
    }

    public async Task<IActionResult> OnPostCodeAsync()
    {
        var state = await flow.ReadAsync(HttpContext);
        if (state is not {Stage: "code", PendingCredential: not null, EnrollmentId: not null})
        {
            return RedirectToPage();
        }
        var code = new string((Code ?? "").Where(char.IsDigit).ToArray());
        var tokens = code.Length is >= 6 and <= 8
            ? await identity.FinalizeTotpSignInAsync(state.PendingCredential, state.EnrollmentId, code, HttpContext.RequestAborted)
            : null;
        if (tokens is null)
        {
            Stage = "code";
            Error = await flow.RecordFailureAsync(HttpContext, state)
                ? "That code did not work. Use the current code from your authenticator app."
                : "Too many attempts. Start again.";
            if (Error.StartsWith("Too many", StringComparison.Ordinal)) Stage = "password";
            return Page();
        }
        return await AdmitAsync(tokens, state.Email);
    }

    public async Task<IActionResult> OnPostEnrollAsync()
    {
        var state = await flow.ReadAsync(HttpContext);
        if (state is not {Stage: "enroll", IdToken: not null, EnrollmentSession: not null})
        {
            return RedirectToPage();
        }
        var code = new string((Code ?? "").Where(char.IsDigit).ToArray());
        var tokens = code.Length is >= 6 and <= 8
            ? await identity.FinalizeTotpEnrollmentAsync(state.IdToken, state.EnrollmentSession, code, HttpContext.RequestAborted)
            : null;
        if (tokens is null)
        {
            Stage = "enroll";
            EnrollmentSecret = state.EnrollmentSecret;
            EnrollmentUri = state.EnrollmentUri;
            Error = await flow.RecordFailureAsync(HttpContext, state)
                ? "That code did not work. Check the time on your phone and try the next code."
                : "Too many attempts. Start again.";
            if (Error.StartsWith("Too many", StringComparison.Ordinal)) Stage = "password";
            return Page();
        }
        logger.LogInformation("staff_totp_enrolled uid={Uid}", tokens.Uid);
        return await AdmitAsync(tokens, state.Email);
    }

    public async Task<IActionResult> OnPostCancelAsync()
    {
        await flow.ClearAsync(HttpContext);
        return RedirectToPage();
    }

    private async Task<IActionResult> AdmitAsync(FirebaseTokens tokens, string email)
    {
        JsonElement profile;
        try
        {
            profile = await api.CallWithTokenAsync(tokens.IdToken, "adminRecordLogin", null, HttpContext.RequestAborted);
        }
        catch (AdminApiException error) when (error.Code == "mfa_required")
        {
            // Password was right but the account has no second factor yet:
            // enrolment is mandatory before any console access.
            var start = await identity.StartTotpEnrollmentAsync(tokens.IdToken, email, HttpContext.RequestAborted);
            if (start is null)
            {
                await flow.ClearAsync(HttpContext);
                Error = "Two-factor enrolment could not be started. Identity Platform MFA (TOTP) must be enabled for this project.";
                return Page();
            }
            await flow.WriteAsync(HttpContext, new LoginFlowState
            {
                Stage = "enroll",
                Email = email,
                IdToken = tokens.IdToken,
                RefreshToken = tokens.RefreshToken,
                Uid = tokens.Uid,
                TokenExpiresAt = tokens.ExpiresAt,
                EnrollmentSession = start.SessionInfo,
                EnrollmentSecret = start.SharedSecretKey,
                EnrollmentUri = start.OtpAuthUri,
            });
            return RedirectToPage();
        }
        catch (AdminApiException error)
        {
            await flow.ClearAsync(HttpContext);
            logger.LogInformation("staff_admission_refused code={Code}", error.Code);
            Stage = "password";
            // Same message for a member account, a disabled or an unknown staff member.
            Error = error.Code == "backend_unavailable"
                ? AdminErrorMessages.For(error.Code)
                : "This account does not have access to the Trust & Safety console.";
            return Page();
        }
        await flow.ClearAsync(HttpContext);
        await session.SignInAsync(tokens, profile);
        return Redirect("/Dashboard");
    }
}
