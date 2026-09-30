using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Admin;

/// <summary>
/// Staff and roles. Granting, changing and disabling are server-checked:
/// nobody changes their own role, nobody grants a role at or above their own,
/// and the last active super admin cannot be removed.
/// </summary>
[RequirePermission("admin.manage_staff")]
public sealed class StaffModel(IAdminApiClient api) : AdminPageModel(api)
{
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync()
    {
        Result = await Load("adminListStaff") ?? default;
    }

    public Task<IActionResult> OnPostGrantAsync(string? email, string? targetUid, string role, string? displayName)
    {
        if (!Vocab.Roles.Contains(role)) return Task.FromResult(Invalid("Choose a role."));
        var e = Clean(email, 254);
        var u = Clean(targetUid, 128);
        if (e is null && u is null) return Task.FromResult(Invalid("Enter the staff member's email or UID. They must already have a sign-in account."));
        return Act("adminUpdateStaffRole", new {email = e, targetUid = u, role, displayName = Clean(displayName, 80)},
            $"Role set to {JsonView.Label(role)}. Their current sessions were ended.");
    }

    public Task<IActionResult> OnPostDisableAsync(string targetUid, string? reason)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Give a reason for disabling access."))
            : Act("adminDisableStaff", new {targetUid, reason = r}, "Staff access disabled and sessions revoked.");
    }

    public Task<IActionResult> OnPostEnableAsync(string targetUid, string? reason)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Give a reason for re-enabling access."))
            : Act("adminEnableStaff", new {targetUid, reason = r}, "Staff access re-enabled.");
    }
}
