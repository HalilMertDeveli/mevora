using System.Text.RegularExpressions;
using Google.Cloud.Firestore;
using Mevora.Web.Models;
using Mevora.Web.Services.Email;
using Microsoft.AspNetCore.Http;

namespace Mevora.Web.Services.Firebase;

public interface IFirebaseSupportService
{
    Task<SupportTicketCreateResult> CreateTicketAsync(
        SupportTicketDraft draft,
        IFormFile? screenshot,
        CancellationToken cancellationToken = default);
}

public sealed record SupportTicketDraft(
    string Name,
    string Email,
    string? UserId,
    string Category,
    string Subject,
    string Description,
    string Priority);

public sealed record SupportTicketCreateResult(
    bool Succeeded,
    string? TicketId,
    string? ErrorMessage,
    bool UsedFirebase);

public sealed class FirebaseSupportService : IFirebaseSupportService
{
    public const long MaxUploadBytes = 5 * 1024 * 1024;
    private static readonly HashSet<string> AllowedContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
    };

    private readonly IFirebaseService _firebase;
    private readonly ISupportNotificationService _notifications;
    private readonly ILogger<FirebaseSupportService> _logger;

    public FirebaseSupportService(
        IFirebaseService firebase,
        ISupportNotificationService notifications,
        ILogger<FirebaseSupportService> logger)
    {
        _firebase = firebase;
        _notifications = notifications;
        _logger = logger;
    }

    public async Task<SupportTicketCreateResult> CreateTicketAsync(
        SupportTicketDraft draft,
        IFormFile? screenshot,
        CancellationToken cancellationToken = default)
    {
        if (!_firebase.IsAvailable || _firebase.Firestore is null)
        {
            _logger.LogWarning("Support ticket rejected: Firebase unavailable ({Reason}).", _firebase.UnavailableReason);
            return new SupportTicketCreateResult(
                false,
                null,
                "Destek sistemi şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.",
                false);
        }

        try
        {
            var now = Timestamp.GetCurrentTimestamp();
            var collection = _firebase.Firestore.Collection("supportTickets");
            var doc = collection.Document();
            var userId = string.IsNullOrWhiteSpace(draft.UserId)
                ? $"web-{doc.Id}"
                : SanitizeUserId(draft.UserId);

            string? attachmentUrl = null;
            var attachments = new List<string>();

            if (screenshot is { Length: > 0 })
            {
                var upload = await UploadScreenshotAsync(doc.Id, screenshot, cancellationToken);
                if (!upload.Succeeded)
                {
                    return new SupportTicketCreateResult(false, null, upload.ErrorMessage, true);
                }

                attachmentUrl = upload.ObjectPath;
                if (!string.IsNullOrEmpty(attachmentUrl))
                {
                    attachments.Add(attachmentUrl);
                }
            }

            var data = new Dictionary<string, object>
            {
                ["id"] = doc.Id,
                ["userId"] = userId,
                ["name"] = draft.Name.Trim(),
                ["email"] = draft.Email.Trim().ToLowerInvariant(),
                ["category"] = draft.Category,
                ["subject"] = draft.Subject.Trim(),
                ["description"] = draft.Description.Trim(),
                ["message"] = draft.Description.Trim(),
                ["priority"] = draft.Priority,
                ["status"] = SupportTicketStatuses.Open,
                ["source"] = "website",
                ["attachments"] = attachments,
                ["createdAt"] = now,
                ["updatedAt"] = now,
            };

            if (!string.IsNullOrEmpty(attachmentUrl))
            {
                data["attachmentUrl"] = attachmentUrl;
            }

            await doc.SetAsync(data, cancellationToken: cancellationToken);
            _logger.LogInformation("Support ticket {TicketId} created via website.", doc.Id);

            try
            {
                await _notifications.NotifyTicketCreatedAsync(draft, doc.Id, userId, cancellationToken);
            }
            catch (Exception notifyEx)
            {
                _logger.LogError(notifyEx, "Post-create notifications failed for ticket {TicketId}.", doc.Id);
            }

            return new SupportTicketCreateResult(true, doc.Id, null, true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create support ticket.");
            return new SupportTicketCreateResult(
                false,
                null,
                "Destek talebi oluşturulamadı. Lütfen daha sonra tekrar deneyin.",
                true);
        }
    }

    private async Task<(bool Succeeded, string? ObjectPath, string? ErrorMessage)> UploadScreenshotAsync(
        string ticketId,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        if (_firebase.Storage is null || string.IsNullOrWhiteSpace(_firebase.StorageBucket))
        {
            return (false, null, "Dosya yükleme şu anda kullanılamıyor. Dosya olmadan tekrar deneyebilirsiniz.");
        }

        if (file.Length <= 0)
        {
            return (true, null, null);
        }

        if (file.Length > MaxUploadBytes)
        {
            return (false, null, "Dosya boyutu en fazla 5 MB olabilir.");
        }

        var contentType = string.IsNullOrWhiteSpace(file.ContentType)
            ? "application/octet-stream"
            : file.ContentType;

        if (!AllowedContentTypes.Contains(contentType))
        {
            return (false, null, "Yalnızca JPEG, PNG veya WebP görselleri yüklenebilir.");
        }

        var extension = contentType switch
        {
            "image/png" => ".png",
            "image/webp" => ".webp",
            _ => ".jpg",
        };

        var safeName = $"{Guid.NewGuid():N}{extension}";
        var objectPath = $"support/{ticketId}/{safeName}";

        try
        {
            await using var stream = file.OpenReadStream();
            await _firebase.Storage.UploadObjectAsync(
                _firebase.StorageBucket,
                objectPath,
                contentType,
                stream,
                cancellationToken: cancellationToken);

            return (true, objectPath, null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Support attachment upload failed for ticket {TicketId}.", ticketId);
            return (false, null, "Ekran görüntüsü yüklenemedi. Dosya olmadan tekrar deneyebilirsiniz.");
        }
    }

    private static string SanitizeUserId(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length > 128)
        {
            trimmed = trimmed[..128];
        }

        return Regex.Replace(trimmed, @"[^\w\-@.]", string.Empty);
    }
}
