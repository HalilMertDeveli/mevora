using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Automation;

/// <summary>
/// Automation jobs that need a human. The actions offered per job come from
/// the backend's per-kind policy — there is no generic "retry everything".
/// </summary>
[RequirePermission("automation.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string Status { get; private set; } = "manual_review";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? cursor)
    {
        Status = status == "failed" ? "failed" : "manual_review";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListManualReviewJobs", new {status = Status, cursor = Cursor, limit = 25}) ?? default;
    }

    public Task<IActionResult> OnPostReviewAsync(string jobId, string action, string? note)
    {
        var n = Clean(note, 4000);
        if (n is null) return Task.FromResult(Invalid(L["A note is required for every job decision."]));
        return action is "retry" or "resolve" or "dismiss" or "escalate"
            ? Act("adminReviewAutomationJob", new {jobId, action, note = n}, L["Job decision recorded: {0}.", L.Code("job." + action)])
            : Task.FromResult(Invalid(L["Unknown action."]));
    }

    public Task<IActionResult> OnPostItemAsync(string itemId, string outcome, string? note)
    {
        var n = Clean(note, 4000);
        if (n is null) return Task.FromResult(Invalid(L["A note is required."]));
        return outcome is "resolved" or "dismissed"
            ? Act("adminResolveReviewItem", new {itemId, outcome, note = n}, L["Review item closed."])
            : Task.FromResult(Invalid(L["Unknown outcome."]));
    }

    public PagerModel Pager => new("/Automation", Result.Str("nextCursor"), new Dictionary<string, string?> {["status"] = Status}, Cursor is not null);
}
