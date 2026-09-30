using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages.Audit;

/// <summary>Read-only view of the append-only audit log. There is no edit or delete anywhere.</summary>
[RequirePermission("audit.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string? Actor { get; private set; }
    public string? Target { get; private set; }
    public string? Action { get; private set; }
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? actor, string? target, string? action, string? cursor)
    {
        Actor = Clean(actor, 128);
        Target = Actor is null ? Clean(target, 300) : null;
        Action = Actor is null && Target is null ? Clean(action, 64) : null;
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListAuditEvents", new {actorAdminId = Actor, targetId = Target, action = Action, cursor = Cursor, limit = 50}) ?? default;
    }

    public PagerModel Pager => new("/Audit", Result.Str("nextCursor"),
        new Dictionary<string, string?> {["actor"] = Actor, ["target"] = Target, ["action"] = Action}, Cursor is not null);
}
