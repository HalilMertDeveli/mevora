using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Localization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Admin.Web.Pages;

/// <summary>
/// Stores the console language in a culture cookie and goes back to the page
/// the switcher was on. POST with antiforgery, and only local return URLs, so
/// neither a link nor another site can change it or bounce someone elsewhere.
/// </summary>
public sealed class LanguageModel(IWebHostEnvironment env) : PageModel
{
    public IActionResult OnGet() => Redirect("/");

    public IActionResult OnPost(string? culture, string? returnUrl)
    {
        if (ConsoleCultures.IsSupported(culture))
        {
            Response.Cookies.Append(
                CookieRequestCultureProvider.DefaultCookieName,
                CookieRequestCultureProvider.MakeCookieValue(new RequestCulture(culture!)),
                new CookieOptions
                {
                    Expires = DateTimeOffset.UtcNow.AddYears(1),
                    HttpOnly = true,
                    IsEssential = true,
                    SameSite = SameSiteMode.Lax,
                    Secure = !env.IsDevelopment() || Request.IsHttps,
                    Path = "/",
                });
        }
        return LocalRedirect(Url.IsLocalUrl(returnUrl) ? returnUrl! : "/");
    }
}
