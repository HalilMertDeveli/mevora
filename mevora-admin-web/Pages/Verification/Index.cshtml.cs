using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Verification;

/// <summary>
/// Identity verification review. Read and escalate only; there is no way to
/// mark anyone verified from the console — only the provider can.
/// </summary>
[RequirePermission("verification.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public static readonly string[] Filters = ["in_review", "error", "declined", "expired"];
    public string Filter { get; private set; } = "in_review";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? filter, string? cursor)
    {
        Filter = Filters.Contains(filter) ? filter! : "in_review";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListVerificationReviews", new {filter = Filter, cursor = Cursor, limit = 25}) ?? default;
    }

    public Task<IActionResult> OnPostEscalateAsync(string uid, string? reason, string? note)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid("Say why this needs review."))
            : Act("adminEscalateVerification", new {uid, reason = r, note = Clean(note, 4000)}, "Opened a verification review case.");
    }

    public PagerModel Pager => new("/Verification", Result.Str("nextCursor"), new Dictionary<string, string?> {["filter"] = Filter}, Cursor is not null);
}
