using Mevora.Web.Configuration;
using Mevora.Web.Models;
using Mevora.Web.Services.Firebase;
using Microsoft.Extensions.Options;

namespace Mevora.Web.Services.Email;

public interface ISupportNotificationService
{
    Task NotifyTicketCreatedAsync(
        SupportTicketDraft draft,
        string ticketId,
        string? resolvedUserId,
        CancellationToken cancellationToken = default);
}

public sealed class SupportNotificationService : ISupportNotificationService
{
    private readonly IEmailService _email;
    private readonly IEmailTemplateService _templates;
    private readonly EmailSettings _emailSettings;
    private readonly SiteSettings _siteSettings;
    private readonly ILogger<SupportNotificationService> _logger;

    public SupportNotificationService(
        IEmailService email,
        IEmailTemplateService templates,
        IOptions<EmailSettings> emailOptions,
        IOptions<SiteSettings> siteOptions,
        ILogger<SupportNotificationService> logger)
    {
        _email = email;
        _templates = templates;
        _emailSettings = emailOptions.Value;
        _siteSettings = siteOptions.Value;
        _logger = logger;
    }

    public async Task NotifyTicketCreatedAsync(
        SupportTicketDraft draft,
        string ticketId,
        string? resolvedUserId,
        CancellationToken cancellationToken = default)
    {
        var model = new SupportEmailModel(
            TicketId: ticketId,
            Name: draft.Name.Trim(),
            Email: draft.Email.Trim(),
            UserId: string.IsNullOrWhiteSpace(resolvedUserId) ? "(none)" : resolvedUserId,
            Category: draft.Category,
            Subject: draft.Subject.Trim(),
            Description: draft.Description.Trim(),
            Priority: draft.Priority,
            Status: SupportTicketStatuses.Open,
            CreatedAt: DateTimeOffset.UtcNow,
            SiteName: _siteSettings.SiteName);

        // Team notification — failure must not roll back the ticket.
        if (!string.IsNullOrWhiteSpace(_emailSettings.SupportEmail))
        {
            var team = await _email.SendAsync(
                new EmailMessage(
                    To: _emailSettings.SupportEmail,
                    Subject: $"[{_siteSettings.SiteName}] New ticket {ticketId}: {draft.Subject.Trim()}",
                    HtmlBody: _templates.RenderSupportTeamNotification(model),
                    PlainTextBody: _templates.PlainTeamNotification(model),
                    ReplyTo: draft.Email.Trim()),
                cancellationToken);

            if (!team.Succeeded && !team.Skipped)
            {
                _logger.LogWarning("Team support email failed for ticket {TicketId}.", ticketId);
            }
        }
        else
        {
            _logger.LogInformation("Team support email skipped: Email:SupportEmail empty.");
        }

        // User confirmation is opt-in (SendUserConfirmation) to avoid mail to unverified addresses.
        if (_emailSettings.SendUserConfirmation)
        {
            var user = await _email.SendAsync(
                new EmailMessage(
                    To: draft.Email.Trim(),
                    Subject: $"{_siteSettings.SiteName} — Destek talebiniz alındı ({ticketId})",
                    HtmlBody: _templates.RenderUserConfirmation(model),
                    PlainTextBody: _templates.PlainUserConfirmation(model)),
                cancellationToken);

            if (!user.Succeeded && !user.Skipped)
            {
                _logger.LogWarning("User confirmation email failed for ticket {TicketId}.", ticketId);
            }
        }
    }
}
