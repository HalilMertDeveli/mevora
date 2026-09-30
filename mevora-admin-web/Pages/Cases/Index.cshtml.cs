using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages.Cases;

[RequirePermission("case.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public static readonly string[] Statuses = ["active", "open", "assigned", "in_review", "waiting", "resolved", "dismissed"];

    public string Status { get; private set; } = "active";
    public string? Type { get; private set; }
    public string Assigned { get; private set; } = "any";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? type, string? assigned, string? cursor)
    {
        Status = Statuses.Contains(status) ? status! : "active";
        Type = Vocab.CaseTypes.Contains(type) ? type : null;
        Assigned = assigned == "me" ? "me" : "any";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListCases", new {status = Status, type = Type, assigned = Assigned, cursor = Cursor, limit = 25}) ?? default;
    }

    public PagerModel Pager => new("/Cases", Result.Str("nextCursor"),
        new Dictionary<string, string?> {["status"] = Status, ["type"] = Type, ["assigned"] = Assigned}, Cursor is not null);
}
