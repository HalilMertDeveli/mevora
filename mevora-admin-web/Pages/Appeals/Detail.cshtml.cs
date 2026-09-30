using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Appeals;

[RequirePermission("appeal.read")]
public sealed class DetailModel(IAdminApiClient api) : AdminPageModel(api)
{
    [FromRoute] public string AppealId { get; set; } = "";
    public JsonElement Appeal { get; private set; }
    public string FormKey { get; } = NewKey();

    public async Task OnGetAsync()
    {
        Appeal = await Load("adminGetAppeal", new {appealId = AppealId}) ?? default;
    }

    public Task<IActionResult> OnPostAssignAsync() =>
        Act("adminAssignAppeal", new {appealId = AppealId}, "Appeal assigned to you.", Back);

    public Task<IActionResult> OnPostResolveAsync(string decision, string? userMessage, string? internalNote, string idempotencyKey)
    {
        var message = Clean(userMessage, 1000);
        if (decision is not ("accept" or "reject")) return Task.FromResult(Invalid("Choose accept or reject.", Back));
        if (message is null) return Task.FromResult(Invalid("Write the message the member will see.", Back));
        return Act("adminResolveAppeal", new {appealId = AppealId, decision, userMessage = message, internalNote = Clean(internalNote, 4000), idempotencyKey},
            decision == "accept" ? "Appeal accepted. Any suspension or ban it covered was lifted by a new restore action." : "Appeal rejected. The decision stands.",
            Back);
    }

    private IActionResult Back() => Redirect($"/Appeals/{Uri.EscapeDataString(AppealId)}");
}
