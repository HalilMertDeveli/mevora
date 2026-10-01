using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.Photos;

/// <summary>
/// Photo review queue over the server-owned moderation ledger. Decisions go
/// to adminReviewPhoto, which writes the ledger through the existing
/// moderation pipeline; this page never touches a profile's photos array.
/// </summary>
[RequirePermission("photo.read")]
public sealed class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public static readonly (string Value, string Label)[] Filters =
    [
        ("manual_review", "Manual review"),
        ("reported", "Reported profiles"),
        ("retries_exhausted", "Processing retries exhausted"),
        ("pending_too_long", "Pending too long"),
    ];

    public string Filter { get; private set; } = "manual_review";
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }
    public string FormKey { get; } = NewKey();

    public async Task OnGetAsync(string? filter, string? cursor)
    {
        Filter = Filters.Any(f => f.Value == filter) ? filter! : "manual_review";
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListPhotoReviews", new {filter = Filter, cursor = Cursor, limit = 24}) ?? default;
    }

    /// <summary>
    /// Streams the image bytes fetched by the backend. The bucket stays
    /// private and no signed URL exists; the response is never cached.
    /// </summary>
    public async Task<IActionResult> OnGetPreviewAsync(string uid, string imageId)
    {
        try
        {
            var preview = await Api.CallAsync("adminGetPhotoPreview", new {uid, imageId}, HttpContext.RequestAborted);
            var contentType = preview.Str("contentType") ?? "";
            if (contentType is not ("image/jpeg" or "image/jpg" or "image/png" or "image/webp"))
            {
                return NotFound();
            }
            Response.Headers.CacheControl = "no-store";
            Response.Headers["Content-Disposition"] = "inline";
            return File(Convert.FromBase64String(preview.Str("dataBase64") ?? ""), contentType);
        }
        catch (AdminApiException error)
        {
            if (error.EndsSession) throw new SessionEndedException();
            return error.IsPermissionDenied ? Forbid() : NotFound();
        }
    }

    public Task<IActionResult> OnPostDecideAsync(string uid, string imageId, string decision, string? reasonCode, string? internalNote, string? caseId, string idempotencyKey, string? filter)
    {
        if (decision is not ("approve" or "reject" or "escalate"))
        {
            return Task.FromResult(Invalid(L["Unknown decision."], () => Back(filter)));
        }
        if (decision == "reject" && !Vocab.PhotoRejectReasons.Contains(reasonCode))
        {
            return Task.FromResult(Invalid(L["Pick a rejection reason."], () => Back(filter)));
        }
        // An approval only publishes a photo that is still on the profile: one
        // the member took off is not put back, and the backend says which it was.
        string Message(JsonElement result) => (decision, result.Str("placement")) switch
        {
            ("approve", "removed_by_member") => L["Photo approved. The member had removed it, so the kept copy was deleted."].Value,
            ("approve", "not_on_profile") => L["Photo approved. It is not on the member's profile and was not added back."].Value,
            ("approve", _) => L["Photo approved and published."].Value,
            ("reject", _) => L["Photo rejected and removed from view."].Value,
            _ => L["Photo escalated to senior review."].Value,
        };
        return Act("adminReviewPhoto", new
        {
            uid,
            imageId,
            decision,
            reasonCode = decision == "approve" ? null : Clean(reasonCode, 64),
            internalNote = Clean(internalNote, 4000),
            caseId = Clean(caseId, 128),
            idempotencyKey,
        }, Message, () => Back(filter));
    }

    // After a decision the reviewed photo leaves the queue, so returning to the
    // same filter lands the reviewer on the next photo.
    private IActionResult Back(string? filter) =>
        Redirect(Filters.Any(f => f.Value == filter) ? $"/Photos?filter={filter}" : "/Photos");

    public PagerModel Pager => new("/Photos", Result.Str("nextCursor"), new Dictionary<string, string?> {["filter"] = Filter}, Cursor is not null);
}
