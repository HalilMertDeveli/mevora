using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Admin.Web.Pages;

[IgnoreAntiforgeryToken]
public sealed class StatusModel : PageModel
{
    public string Title { get; private set; } = "Something went wrong";
    public string Message { get; private set; } = "";

    public void OnGet(int? code) => Describe(code);

    public void OnPost(int? code) => Describe(code);

    private void Describe(int? code)
    {
        var status = code ?? 500;
        Response.StatusCode = status;
        (Title, Message) = status switch
        {
            400 => ("Request refused", "The request was malformed or its security token expired. Go back, refresh the page and try again."),
            403 => ("Not permitted", "Your role does not include this part of the console. Access is decided by the server for every request."),
            404 => ("Not found", "That page or record does not exist."),
            429 => ("Slow down", "Too many requests in a short time. Wait a minute and try again."),
            _ => ("Something went wrong", "The error was logged. Try again shortly."),
        };
    }
}
