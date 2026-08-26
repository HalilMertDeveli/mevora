using System.Net;
using System.Net.Mail;
using System.Text;
using Mevora.Web.Configuration;
using Microsoft.Extensions.Options;

namespace Mevora.Web.Services.Email;

public interface IEmailService
{
    bool IsAvailable { get; }
    Task<EmailSendResult> SendAsync(EmailMessage message, CancellationToken cancellationToken = default);
}

public sealed record EmailMessage(
    string To,
    string Subject,
    string HtmlBody,
    string? PlainTextBody = null,
    string? ReplyTo = null);

public sealed record EmailSendResult(bool Succeeded, string? ErrorMessage, bool Skipped);

public sealed class SmtpEmailService : IEmailService
{
    private readonly EmailSettings _settings;
    private readonly ILogger<SmtpEmailService> _logger;

    public SmtpEmailService(IOptions<EmailSettings> options, ILogger<SmtpEmailService> logger)
    {
        _settings = options.Value;
        _logger = logger;
    }

    public bool IsAvailable => _settings.IsConfigured;

    public async Task<EmailSendResult> SendAsync(EmailMessage message, CancellationToken cancellationToken = default)
    {
        if (!_settings.Enabled)
        {
            _logger.LogInformation("Email skipped: Email:Enabled is false.");
            return new EmailSendResult(false, null, Skipped: true);
        }

        if (!_settings.IsConfigured)
        {
            _logger.LogWarning("Email skipped: SMTP/support mailbox is not configured.");
            return new EmailSendResult(false, "Email is not configured.", Skipped: true);
        }

        if (string.IsNullOrWhiteSpace(message.To) || string.IsNullOrWhiteSpace(message.Subject))
        {
            return new EmailSendResult(false, "Invalid email message.", Skipped: false);
        }

        try
        {
            using var client = new SmtpClient(_settings.Host, _settings.Port)
            {
                EnableSsl = _settings.UseSsl,
                DeliveryMethod = SmtpDeliveryMethod.Network,
                Timeout = 30_000,
            };

            if (!string.IsNullOrWhiteSpace(_settings.Username))
            {
                client.Credentials = new NetworkCredential(_settings.Username, _settings.Password ?? string.Empty);
            }

            using var mail = new MailMessage
            {
                From = new MailAddress(_settings.SenderEmail, _settings.SenderName, Encoding.UTF8),
                Subject = message.Subject,
                SubjectEncoding = Encoding.UTF8,
                BodyEncoding = Encoding.UTF8,
                IsBodyHtml = true,
                Body = message.HtmlBody,
            };

            mail.To.Add(message.To);
            if (!string.IsNullOrWhiteSpace(message.ReplyTo))
            {
                mail.ReplyToList.Add(message.ReplyTo);
            }

            await client.SendMailAsync(mail, cancellationToken);
            _logger.LogInformation("Email sent for subject '{Subject}'.", message.Subject);
            return new EmailSendResult(true, null, Skipped: false);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email for subject '{Subject}'.", message.Subject);
            return new EmailSendResult(false, "Email could not be sent.", Skipped: false);
        }
    }
}
