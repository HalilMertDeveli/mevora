using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Web.Pages;

[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
[IgnoreAntiforgeryToken]
public class ErrorModel : PageModel
{
    public string? RequestId { get; set; }
    public int StatusCodeValue { get; set; } = 500;
    public bool Is404 => StatusCodeValue == 404;

    public void OnGet(int? statusCode = null)
    {
        RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier;
        StatusCodeValue = statusCode is > 0
            ? statusCode.Value
            : (HttpContext.Response.StatusCode > 0 ? HttpContext.Response.StatusCode : 500);

        Response.StatusCode = StatusCodeValue;
    }
}
