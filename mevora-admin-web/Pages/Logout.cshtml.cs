using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Admin.Web.Pages;

[AllowAnonymous]
public sealed class LogoutModel(IStaffSession session) : PageModel
{
    public void OnGet()
    {
    }

    /// <summary>POST only, antiforgery-checked: a link cannot sign anyone out.</summary>
    public async Task<IActionResult> OnPostAsync()
    {
        // Removes the server-side ticket, not just the cookie.
        await session.SignOutAsync();
        return Redirect("/Login");
    }
}
