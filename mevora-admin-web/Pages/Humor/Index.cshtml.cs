using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Humor;

/// <summary>Humor Lab queue; decisions run through the existing humor moderation code.</summary>
[RequirePermission("humor.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public static readonly string[] Statuses = ["needs_review", "pending", "rejected", "approved"];
    public string Status { get; private set; } = "needs_review";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? cursor)
    {
        Status = Statuses.Contains(status) ? status! : "needs_review";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListHumorReviews", new {status = Status, cursor = Cursor, limit = 25}) ?? default;
    }

    public Task<IActionResult> OnPostDecideAsync(string contentId, string decision, string? note) =>
        decision is "approve" or "reject" or "escalate"
            ? Act("adminReviewHumorContent", new {contentId, decision, note = Clean(note, 4000)},
                decision == "escalate" ? "Escalated." : $"Content {(decision == "approve" ? "approved" : "rejected")}.",
                () => Redirect($"/Humor?status={Status}"))
            : Task.FromResult(Invalid("Unknown decision."));

    public PagerModel Pager => new("/Humor", Result.Str("nextCursor"), new Dictionary<string, string?> {["status"] = Status}, Cursor is not null);
}
