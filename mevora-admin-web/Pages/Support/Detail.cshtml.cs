using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Support;

/// <summary>
/// One ticket. Replies go to the member-visible thread; internal notes go to a
/// staff-only collection. They are separate handlers posting to separate
/// commands, so a note can never be sent to the member by mistake.
/// </summary>
[RequirePermission("support.read")]
public sealed class DetailModel(IAdminApiClient api) : AdminPageModel(api)
{
    [FromRoute] public string TicketId { get; set; } = "";
    public JsonElement Ticket { get; private set; }
    public string FormKey { get; } = NewKey();

    public async Task OnGetAsync()
    {
        Ticket = await Load("adminGetSupportTicket", new {ticketId = TicketId}) ?? default;
    }

    public async Task<IActionResult> OnGetAttachmentAsync(int index)
    {
        try
        {
            var file = await Api.CallAsync("adminGetSupportAttachment", new {ticketId = TicketId, index}, HttpContext.RequestAborted);
            var type = file.Str("contentType") ?? "";
            if (type is not ("image/jpeg" or "image/jpg" or "image/png" or "image/webp")) return NotFound();
            Response.Headers.CacheControl = "no-store";
            return File(Convert.FromBase64String(file.Str("dataBase64") ?? ""), type);
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return NotFound();
        }
    }

    public Task<IActionResult> OnPostReplyAsync(string? text, string idempotencyKey)
    {
        var t = Clean(text, 4000);
        return t is null
            ? Task.FromResult(Invalid(L["The reply is empty."], Back))
            : Act("adminReplySupportTicket", new {ticketId = TicketId, text = t, idempotencyKey}, L["Reply sent to the member's ticket."], Back);
    }

    public Task<IActionResult> OnPostNoteAsync(string? text)
    {
        var t = Clean(text, 4000);
        return t is null
            ? Task.FromResult(Invalid(L["The note is empty."], Back))
            : Act("adminAddSupportNote", new {ticketId = TicketId, text = t}, L["Internal note added."], Back);
    }

    public Task<IActionResult> OnPostAssignAsync() =>
        Act("adminAssignSupportTicket", new {ticketId = TicketId}, L["Ticket assigned to you."], Back);

    public Task<IActionResult> OnPostPriorityAsync(string priority) =>
        priority is "low" or "normal" or "high" or "urgent"
            ? Act("adminUpdateSupportTicket", new {ticketId = TicketId, priority}, L["Priority updated."], Back)
            : Task.FromResult(Invalid(L["Unknown priority."], Back));

    public Task<IActionResult> OnPostResolveAsync(string outcome, string? resolutionNote) =>
        outcome is "resolved" or "closed"
            ? Act("adminResolveSupportTicket", new {ticketId = TicketId, outcome, resolutionNote = Clean(resolutionNote, 4000)}, L["Ticket {0}.", L.Code(outcome)], Back)
            : Task.FromResult(Invalid(L["Unknown outcome."], Back));

    public Task<IActionResult> OnPostEscalateAsync(string? reason, string priority, string idempotencyKey)
    {
        var r = Clean(reason, 500);
        return r is null
            ? Task.FromResult(Invalid(L["Say why this goes to Trust & Safety."], Back))
            : Act("adminEscalateSupportTicket", new {ticketId = TicketId, reason = r, priority, idempotencyKey}, L["Escalated to Trust & Safety."], Back);
    }

    private IActionResult Back() => Redirect($"/Support/{Uri.EscapeDataString(TicketId)}");
}
