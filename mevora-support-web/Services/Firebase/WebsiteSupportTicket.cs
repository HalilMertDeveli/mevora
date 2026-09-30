using System.Text.RegularExpressions;
using Google.Cloud.Firestore;
using Mevora.Web.Models;

namespace Mevora.Web.Services.Firebase;

/// <summary>
/// Shape of a <c>supportTickets</c> document written by the public website.
/// The visitor is not signed in, so the ticket never claims a member identity:
/// <c>userId</c> is always <c>web-{ticketId}</c>, which no Firebase uid can equal,
/// and whatever the visitor typed in the optional user id field is kept apart in
/// <c>claimedUserId</c> for staff to confirm by hand. The app lists a member's
/// tickets with <c>where('userId' == uid)</c>, and account export/deletion query the
/// same field, so a real uid in <c>userId</c> would let anyone plant a ticket there.
/// </summary>
public static class WebsiteSupportTicket
{
    public const string Source = "website";
    public const string UserIdPrefix = "web-";
    public const int MaxClaimedUserIdLength = 128;

    public static string UserIdFor(string ticketId) => $"{UserIdPrefix}{ticketId}";

    /// <summary>
    /// Trims, caps and strips the visitor-typed id; blank input yields <c>null</c>.
    /// The result is an unverified claim, never an identity.
    /// </summary>
    public static string? NormalizeClaimedUserId(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (trimmed.Length > MaxClaimedUserIdLength)
        {
            trimmed = trimmed[..MaxClaimedUserIdLength];
        }

        var cleaned = Regex.Replace(trimmed, @"[^\w\-@.]", string.Empty);
        return cleaned.Length == 0 ? null : cleaned;
    }

    public static Dictionary<string, object> BuildDocument(
        string ticketId,
        SupportTicketDraft draft,
        Timestamp now,
        string? attachmentUrl)
    {
        var attachments = new List<string>();
        if (!string.IsNullOrEmpty(attachmentUrl))
        {
            attachments.Add(attachmentUrl);
        }

        var data = new Dictionary<string, object>
        {
            ["id"] = ticketId,
            ["userId"] = UserIdFor(ticketId),
            ["name"] = draft.Name.Trim(),
            ["email"] = draft.Email.Trim().ToLowerInvariant(),
            ["category"] = draft.Category,
            ["subject"] = draft.Subject.Trim(),
            ["description"] = draft.Description.Trim(),
            ["message"] = draft.Description.Trim(),
            ["priority"] = draft.Priority,
            ["status"] = SupportTicketStatuses.Open,
            ["source"] = Source,
            ["attachments"] = attachments,
            ["createdAt"] = now,
            ["updatedAt"] = now,
        };

        var claimedUserId = NormalizeClaimedUserId(draft.UserId);
        if (claimedUserId is not null)
        {
            data["claimedUserId"] = claimedUserId;
        }

        if (!string.IsNullOrEmpty(attachmentUrl))
        {
            data["attachmentUrl"] = attachmentUrl;
        }

        return data;
    }
}
