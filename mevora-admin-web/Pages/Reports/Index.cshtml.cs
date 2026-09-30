using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Reports;

[RequirePermission("report.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string Status { get; private set; } = "open";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync(string? status, string? cursor)
    {
        Status = status is "resolved" or "dismissed" or "all" ? status : "open";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListReports", new {status = Status, cursor = Cursor, limit = 25}) ?? default;
    }

    public Task<IActionResult> OnPostResolveAsync(string reportId, string outcome, string code, string? note) =>
        outcome is "resolved" or "dismissed" && Vocab.ResolutionCodes.Contains(code)
            ? Act("adminResolveUserReport", new {reportId, outcome, code, note = Clean(note, 4000)}, L["Report {0}.", L.Code(outcome)])
            : Task.FromResult(Invalid(L["Choose an outcome and a resolution code."]));

    public async Task<IActionResult> OnPostOpenCaseAsync(string reportId)
    {
        try
        {
            var result = await Api.CallAsync("adminOpenReportCase", new {reportId});
            return Redirect($"/Cases/{Uri.EscapeDataString(result.S("caseId", ""))}");
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return Invalid(L.Error(error));
        }
    }

    public PagerModel Pager => new("/Reports", Result.Str("nextCursor"), new Dictionary<string, string?> {["status"] = Status}, Cursor is not null);
}
