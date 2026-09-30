using System.Globalization;
using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Users;

/// <summary>
/// The user operations screen. Read: overview + safety timeline. Act: warn,
/// suspend, ban, restore, require re-verification, open a case. Every action
/// is one explicit admin command; this page never writes data itself.
/// </summary>
[RequirePermission("user.read")]
public sealed class DetailModel(IAdminApiClient api) : AdminPageModel(api)
{
    [FromRoute] public string Uid { get; set; } = "";

    public JsonElement Overview { get; private set; }
    public JsonElement Timeline { get; private set; }
    public string FormKey { get; } = NewKey();

    /// <summary>Set when arriving from a case, so decisions are linked to it.</summary>
    public string? LinkedCaseId { get; private set; }

    public async Task<IActionResult> OnGetAsync(long? before, string? caseId)
    {
        LinkedCaseId = caseId is { Length: > 0 and <= 128 } && caseId.All(ch => char.IsLetterOrDigit(ch) || ch is '_' or '-') ? caseId : null;
        await LoadAsync(includeSensitive: false, justification: null, before);
        return Page();
    }

    /// <summary>Reveal contact details. Rendered directly (never redirected) and never cached.</summary>
    public async Task<IActionResult> OnPostRevealAsync(string? justification)
    {
        var reason = Clean(justification, 300);
        if (reason is null || reason.Length < 5)
        {
            return Invalid("Give a short justification (it is recorded) before revealing contact details.", Back);
        }
        await LoadAsync(includeSensitive: true, justification: reason, before: null);
        return Page();
    }

    public Task<IActionResult> OnPostWarnAsync(string reasonCode, string? userMessage, string? caseId, string idempotencyKey) =>
        Act("adminWarnUser", new
        {
            uid = Uid,
            reasonCode,
            userMessage = Clean(userMessage, 1000),
            caseId = Clean(caseId, 128),
            idempotencyKey,
        }, "Warning issued.", Back);

    public Task<IActionResult> OnPostSuspendAsync(string reasonCode, string duration, int? customHours, string? internalNote, string? caseId, string idempotencyKey)
    {
        int hours;
        if (duration == "custom")
        {
            if (customHours is not { } h || h < Vocab.MinSuspensionHours || h > Vocab.MaxSuspensionHours)
            {
                return Task.FromResult(Invalid($"A custom suspension must be between {Vocab.MinSuspensionHours} and {Vocab.MaxSuspensionHours} hours.", Back));
            }
            hours = h;
        }
        else if (!int.TryParse(duration, NumberStyles.Integer, CultureInfo.InvariantCulture, out hours) ||
                 !Vocab.SuspensionPresets.Any(p => p.Value == duration))
        {
            return Task.FromResult(Invalid("Choose a suspension length.", Back));
        }
        var note = Clean(internalNote, 4000);
        if (note is null)
        {
            return Task.FromResult(Invalid("An internal note is required for a suspension.", Back));
        }
        return Act("adminSuspendUser", new
        {
            uid = Uid,
            reasonCode,
            durationHours = hours,
            internalNote = note,
            caseId = Clean(caseId, 128),
            idempotencyKey,
        }, $"Account suspended for {hours} hour(s).", Back);
    }

    public Task<IActionResult> OnPostBanAsync(string reasonCode, string? internalNote, string? confirmWord, string? caseId, string idempotencyKey)
    {
        if (!string.Equals(confirmWord?.Trim(), "BAN", StringComparison.Ordinal))
        {
            return Task.FromResult(Invalid("Type BAN to confirm a permanent ban.", Back));
        }
        var note = Clean(internalNote, 4000);
        if (note is null)
        {
            return Task.FromResult(Invalid("An internal note is required for a ban.", Back));
        }
        return Act("adminBanUser", new {uid = Uid, reasonCode, internalNote = note, caseId = Clean(caseId, 128), idempotencyKey},
            "Account permanently banned. Sign-in is disabled.", Back);
    }

    public Task<IActionResult> OnPostRestoreAsync(string reasonCode, string? internalNote, string idempotencyKey)
    {
        var note = Clean(internalNote, 4000);
        if (note is null)
        {
            return Task.FromResult(Invalid("An internal note is required to restore an account.", Back));
        }
        return Act("adminRestoreUser", new {uid = Uid, reasonCode, internalNote = note, idempotencyKey}, "Account restored.", Back);
    }

    public Task<IActionResult> OnPostReverifyAsync(string reasonCode, string? internalNote, string idempotencyKey)
    {
        var note = Clean(internalNote, 4000);
        if (note is null)
        {
            return Task.FromResult(Invalid("An internal note is required.", Back));
        }
        return Act("adminRequireReverification", new {uid = Uid, reasonCode, internalNote = note, idempotencyKey},
            "Re-verification required. The verified badge was removed until the member verifies again with the provider.", Back);
    }

    public async Task<IActionResult> OnPostOpenCaseAsync(string type, string reasonCode, string priority, string? summary)
    {
        var text = Clean(summary, 300);
        if (text is null)
        {
            return Invalid("Add a short summary for the case.", Back);
        }
        try
        {
            var result = await Api.CallAsync("adminOpenCase", new {type, subjectUserId = Uid, reasonCode, priority, summary = text});
            return Redirect($"/Cases/{Uri.EscapeDataString(result.S("caseId", ""))}");
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return Invalid(AdminErrorMessages.For(error), Back);
        }
    }

    private IActionResult Back() => Redirect($"/Users/{Uri.EscapeDataString(Uid)}");

    private async Task LoadAsync(bool includeSensitive, string? justification, long? before)
    {
        var overview = Load("adminGetUserOverview", new {uid = Uid, includeSensitive, justification});
        var timeline = Load("adminGetUserSafetyTimeline", new {uid = Uid, beforeMs = before, limit = 25});
        Overview = await overview ?? default;
        Timeline = await timeline ?? default;
    }

    public string Status => Overview.Get("account").S("accountStatus", "unknown");
    public bool IsRestricted => Status is "suspended" or "banned";
}
