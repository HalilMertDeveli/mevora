using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Admin;

/// <summary>
/// One colleague: record, sign-in facts, a bounded activity summary and the
/// controls the owner uses day to day — change role, disable / re-enable,
/// end sessions, resend the password-setup email. The owner's own record shows
/// no controls; the backend refuses them anyway.
/// </summary>
[RequirePermission("admin.manage_staff")]
public sealed class StaffDetailModel(IAdminApiClient api, IFirebaseIdentityClient identity) : AdminPageModel(api)
{
    [FromRoute]
    public string Uid { get; set; } = "";

    public JsonElement Data { get; private set; }

    public JsonElement Staff => Data.Get("staff");

    public bool IsSelf => Uid == User.StaffUid();

    public bool IsProtected => IsSelf || Staff.Bool("isOwner");

    /// <summary>Activity counters shown on the page, in reading order.</summary>
    public static readonly (string Key, string Label)[] ActivityTiles =
    [
        ("casesResolved", "Cases resolved"),
        ("reportsResolved", "Reports resolved"),
        ("photosReviewed", "Photos reviewed"),
        ("usersWarned", "Users warned"),
        ("usersSuspended", "Users suspended"),
        ("usersBanned", "Users banned"),
        ("usersRestored", "Users restored"),
        ("supportReplies", "Support replies"),
        ("supportResolved", "Tickets resolved"),
        ("appealsResolved", "Appeals decided"),
        ("verificationActions", "Verification actions"),
    ];

    private IActionResult Back() => Redirect($"/Admin/Staff/{Uri.EscapeDataString(Uid)}");

    public async Task OnGetAsync()
    {
        Data = await Load("adminGetStaff", new {targetUid = Uid}) ?? default;
    }

    public Task<IActionResult> OnPostRoleAsync(string? role)
    {
        if (role is null || !Vocab.GrantableRoles.Contains(role)) return Task.FromResult(Invalid("Choose a role.", Back));
        return Act("adminUpdateStaffRole", new {targetUid = Uid, role},
            $"Role changed to {JsonView.Label(role)}. Their current sessions were ended.", Back);
    }

    public Task<IActionResult> OnPostDisableAsync(string? reason)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Give a reason for disabling access.", Back))
            : Act("adminDisableStaff", new {targetUid = Uid, reason = r}, "Access disabled and sessions ended. It takes effect on their next request.", Back);
    }

    public Task<IActionResult> OnPostEnableAsync(string? reason)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Give a reason for re-enabling access.", Back))
            : Act("adminEnableStaff", new {targetUid = Uid, reason = r}, "Access re-enabled. They sign in again with two-factor authentication.", Back);
    }

    public Task<IActionResult> OnPostRevokeAsync(string? reason)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Give a reason for ending their sessions.", Back))
            : Act("adminRevokeStaffSessions", new {targetUid = Uid, reason = r}, "All their console sessions were ended. They must sign in again.", Back);
    }

    public async Task<IActionResult> OnPostActivationAsync()
    {
        JsonElement result;
        try
        {
            // The backend checks the permission, protects the owner and audits
            // the request; only then does this server ask Firebase to send.
            result = await Api.CallAsync("adminIssueStaffActivation", new {targetUid = Uid});
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return Invalid(AdminErrorMessages.For(error), Back);
        }
        if (result.Str("email") is { Length: > 0 } email && await identity.SendPasswordSetupEmailAsync(email, HttpContext.RequestAborted))
        {
            Flash = "Firebase emailed them a password-setup link.";
        }
        else
        {
            FlashError = "The password-setup email could not be sent. Try again shortly.";
        }
        return Back();
    }
}
