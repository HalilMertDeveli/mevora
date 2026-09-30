using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Cases;

[RequirePermission("case.read")]
public sealed class DetailModel(IAdminApiClient api) : AdminPageModel(api)
{
    [FromRoute] public string CaseId { get; set; } = "";
    public JsonElement Case { get; private set; }

    public async Task OnGetAsync()
    {
        Case = await Load("adminGetCase", new {caseId = CaseId}) ?? default;
    }

    public bool IsClosed => Case.Str("status") is "resolved" or "dismissed";
    public bool HeldByMe => Case.Str("assignedTo") == User.StaffUid();

    public Task<IActionResult> OnPostClaimAsync() =>
        Act("adminAssignCase", new {caseId = CaseId}, L["Case assigned to you."], Back);

    public Task<IActionResult> OnPostUnassignAsync() =>
        Act("adminAssignCase", new {caseId = CaseId, unassign = true}, L["Case returned to the queue."], Back);

    public Task<IActionResult> OnPostStatusAsync(string status) =>
        status is "in_review" or "waiting" or "open"
            ? Act("adminSetCaseStatus", new {caseId = CaseId, status}, L["Case moved to {0}.", L.Code(status)], Back)
            : Task.FromResult(Invalid(L["Unknown status."], Back));

    public Task<IActionResult> OnPostResolveAsync(string outcome, string code, string? note) =>
        outcome is "resolved" or "dismissed" && Vocab.ResolutionCodes.Contains(code)
            ? Act("adminResolveCase", new {caseId = CaseId, outcome, code, note = Clean(note, 4000)}, L["Case {0}.", L.Code(outcome)], Back)
            : Task.FromResult(Invalid(L["Choose an outcome and a resolution code."], Back));

    public Task<IActionResult> OnPostEscalateAsync(string? reason, string? note)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid(L["Say why the case is being escalated."], Back))
            : Act("adminEscalateCase", new {caseId = CaseId, reason = r, note = Clean(note, 4000)}, L["Case escalated to senior review."], Back);
    }

    public Task<IActionResult> OnPostNoteAsync(string? text)
    {
        var t = Clean(text, 4000);
        return t is null
            ? Task.FromResult(Invalid(L["The note is empty."], Back))
            : Act("adminAddCaseNote", new {caseId = CaseId, text = t}, L["Note added."], Back);
    }

    private IActionResult Back() => Redirect($"/Cases/{Uri.EscapeDataString(CaseId)}");
}
