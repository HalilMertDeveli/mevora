using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.RateLimiting;

namespace Mevora.Admin.Web.Pages.Users;

[RequirePermission("user.read")]
[EnableRateLimiting("search")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string? Q { get; private set; }
    public string Mode { get; private set; } = "auto";
    public string? Status { get; private set; }
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }
    public bool Searched { get; private set; }

    public async Task OnGetAsync(string? q, string? mode, string? status, string? cursor)
    {
        Q = Clean(q, 128);
        Mode = mode is "uid" or "email" or "phone" or "name" ? mode : "auto";
        Status = status is "suspended" or "banned" ? status : null;
        Cursor = Clean(cursor, 1024);
        if (Q is null && Status is null)
        {
            return;
        }
        if (Q is {Length: < 2} && Status is null)
        {
            ErrorMessage = "Enter at least two characters.";
            return;
        }
        Searched = true;
        Result = await Load("adminSearchUsers", new
        {
            query = Q ?? "",
            mode = Status is not null && Q is null ? "status" : Mode,
            status = Status,
            cursor = Cursor,
            limit = 20,
        }) ?? default;
    }

    public PagerModel Pager => new("/Users", Result.Str("nextCursor"),
        new Dictionary<string, string?> {["q"] = Q, ["mode"] = Mode == "auto" ? null : Mode, ["status"] = Status}, Cursor is not null);
}
