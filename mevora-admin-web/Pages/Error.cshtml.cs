using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Admin.Web.Pages;

[IgnoreAntiforgeryToken]
public sealed class ErrorModel : PageModel
{
    public string? RequestId { get; private set; }

    public void OnGet()
    {
        Response.StatusCode = 500;
        var id = Activity.Current?.TraceId.ToString() ?? HttpContext.TraceIdentifier;
        RequestId = id.Length > 12 ? id[..12] : id;
    }
}
