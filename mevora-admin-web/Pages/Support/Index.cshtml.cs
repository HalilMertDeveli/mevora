using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages.Support;

[RequirePermission("support.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public static readonly string[] Statuses = ["active", "open", "in_progress", "resolved", "closed", "all"];
    public string Status { get; private set; } = "active";
    public string Assigned { get; private set; } = "any";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? assigned, string? cursor)
    {
        Status = Statuses.Contains(status) ? status! : "active";
        Assigned = assigned == "me" ? "me" : "any";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListSupportTickets", new {status = Status, assigned = Assigned, cursor = Cursor, limit = 25}) ?? default;
    }

    public PagerModel Pager => new("/Support", Result.Str("nextCursor"),
        new Dictionary<string, string?> {["status"] = Status, ["assigned"] = Assigned}, Cursor is not null);
}
