using System.Text.Json;
using Mevora.Admin.Web.Resources;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Localization;

namespace Mevora.Admin.Web.Pages;

/// <summary>
/// Base for every console page: one way to read, one way to act, one way to
/// show errors. Mutations always redirect (post/redirect/get) so a refresh
/// never resubmits a decision; each form carries its own idempotency key, so
/// even a double-click is a single decision on the backend.
///
/// Messages are produced in the staff member's chosen language at the moment
/// they are shown or flashed.
/// </summary>
public abstract class AdminPageModel(IAdminApiClient api) : PageModel
{
    protected IAdminApiClient Api { get; } = api;

    private IStringLocalizer? _l;

    /// <summary>The console's string table in the request's language.</summary>
    protected IStringLocalizer L => _l ??= HttpContext.RequestServices.GetRequiredService<IStringLocalizer<SharedResource>>();

    [TempData] public string? Flash { get; set; }
    [TempData] public string? FlashError { get; set; }

    public string? ErrorMessage { get; protected set; }

    public bool Can(string permission) => User.Can(permission);

    /// <summary>A fresh key for one rendered form.</summary>
    public static string NewKey() => $"web-{Guid.NewGuid():N}";

    /// <summary>Loads data for the page; errors become a banner, not a crash.</summary>
    protected async Task<JsonElement?> Load(string command, object? payload = null)
    {
        try
        {
            return await Api.CallAsync(command, payload, HttpContext.RequestAborted);
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession)
            {
                throw new SessionEndedException();
            }
            ErrorMessage = L.Error(error);
            return null;
        }
    }

    /// <summary>Runs one decision, flashes the outcome, and redirects.</summary>
    protected Task<IActionResult> Act(string command, object payload, string success, Func<IActionResult>? redirect = null) =>
        Act(command, payload, _ => success, redirect);

    /// <summary>As above, for a confirmation that depends on what the backend did.</summary>
    protected async Task<IActionResult> Act(string command, object payload, Func<JsonElement, string> success, Func<IActionResult>? redirect = null)
    {
        try
        {
            Flash = success(await Api.CallAsync(command, payload, HttpContext.RequestAborted));
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession)
            {
                throw new SessionEndedException();
            }
            FlashError = L.Error(error);
        }
        return redirect?.Invoke() ?? RedirectToPage();
    }

    /// <summary>Validation failure before anything is sent to the backend.</summary>
    protected IActionResult Invalid(string message, Func<IActionResult>? redirect = null)
    {
        FlashError = message;
        return redirect?.Invoke() ?? RedirectToPage();
    }

    protected static string? Clean(string? value, int max)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        return trimmed.Length > max ? trimmed[..max] : trimmed;
    }
}

/// <summary>Thrown when the backend says the staff session is over; handled by middleware.</summary>
public sealed class SessionEndedException : Exception;
