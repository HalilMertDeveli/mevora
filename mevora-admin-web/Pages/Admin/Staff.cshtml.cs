using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Admin;

/// <summary>
/// The staff list and "Add staff". Every rule is the backend's: super_admin is
/// never granted here, the owner's record cannot be changed, nobody acts on
/// themselves, and each change is audited.
///
/// Adding a colleague never shows or sets a password: the backend creates the
/// login with a random password nobody sees, and this server asks Firebase to
/// email the colleague a password-setup link. MFA enrolment follows at their
/// first console sign-in.
/// </summary>
[RequirePermission("admin.manage_staff")]
public sealed class StaffModel(IAdminApiClient api, IFirebaseIdentityClient identity) : AdminPageModel(api)
{
    public JsonElement Result { get; private set; }

    public string FormKey { get; } = NewKey();

    public async Task OnGetAsync()
    {
        Result = await Load("adminListStaff") ?? default;
    }

    public async Task<IActionResult> OnPostCreateAsync(string? email, string? displayName, string? role, string? idempotencyKey)
    {
        var e = Clean(email, 254);
        var name = Clean(displayName, 80);
        if (e is null || name is null || name.Length < 2) return Invalid("Enter the colleague's work email and name.");
        if (role is null || !Vocab.GrantableRoles.Contains(role)) return Invalid("Choose a role.");
        JsonElement created;
        try
        {
            created = await Api.CallAsync("adminCreateStaff", new {email = e, displayName = name, role, idempotencyKey});
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return Invalid(AdminErrorMessages.For(error));
        }
        var uid = created.Str("uid") ?? "";
        var detail = $"/Admin/Staff/{Uri.EscapeDataString(uid)}";
        if (!created.Bool("accountCreated"))
        {
            Flash = $"{name} added as {JsonView.Label(role)} using their existing sign-in. They set up two-factor authentication at their next console sign-in.";
            return Redirect(detail);
        }
        if (await identity.SendPasswordSetupEmailAsync(created.Str("email") ?? e, HttpContext.RequestAborted))
        {
            Flash = $"{name} added as {JsonView.Label(role)}. Firebase emailed them a link to set their password; two-factor setup follows at first sign-in.";
        }
        else
        {
            FlashError = $"{name} was added, but the password-setup email could not be sent. Use \"Send password-setup email\" on their page.";
        }
        return Redirect(detail);
    }
}
