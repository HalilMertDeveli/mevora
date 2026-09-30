using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Admin.Web.Pages;

public sealed class IndexModel : PageModel
{
    public IActionResult OnGet() => Redirect("/Dashboard");
}
