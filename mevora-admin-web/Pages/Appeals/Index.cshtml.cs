using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Appeals;

[RequirePermission("appeal.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string Status { get; private set; } = "open";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? cursor)
    {
        Status = status is "in_review" or "resolved" ? status : "open";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListAppeals", new {status = Status, cursor = Cursor, limit = 25}) ?? default;
    }

    /// <summary>File an appeal for a member who wrote in (e.g. a banned member via the support site).</summary>
    public async Task<IActionResult> OnPostFileAsync(string userId, string moderationActionId, string? reason, string? ticketId)
    {
        var r = Clean(reason, 2000);
        if (r is null || r.Length < 10)
        {
            return Invalid("Summarise the member's appeal (at least 10 characters).");
        }
        try
        {
            var result = await Api.CallAsync("adminOpenAppeal", new {userId = userId.Trim(), moderationActionId = moderationActionId.Trim(), reason = r, ticketId = Clean(ticketId, 128)});
            Flash = result.Bool("created") ? "Appeal filed." : "An appeal for that decision already exists.";
            return Redirect($"/Appeals/{Uri.EscapeDataString(result.S("appealId", ""))}");
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return Invalid(AdminErrorMessages.For(error));
        }
    }

    public PagerModel Pager => new("/Appeals", Result.Str("nextCursor"), new Dictionary<string, string?> {["status"] = Status}, Cursor is not null);
}
