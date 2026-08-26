using System.Net;
using System.Text;

namespace Mevora.Web.Services.Email;

public interface IEmailTemplateService
{
    string RenderSupportTeamNotification(SupportEmailModel model);
    string RenderUserConfirmation(SupportEmailModel model);
    string PlainTeamNotification(SupportEmailModel model);
    string PlainUserConfirmation(SupportEmailModel model);
}

public sealed record SupportEmailModel(
    string TicketId,
    string Name,
    string Email,
    string UserId,
    string Category,
    string Subject,
    string Description,
    string Priority,
    string Status,
    DateTimeOffset CreatedAt,
    string SiteName);

public sealed class EmailTemplateService : IEmailTemplateService
{
    private readonly IWebHostEnvironment _env;

    public EmailTemplateService(IWebHostEnvironment env)
    {
        _env = env;
    }

    public string RenderSupportTeamNotification(SupportEmailModel model)
        => RenderFile("SupportTicketCreated.html", model);

    public string RenderUserConfirmation(SupportEmailModel model)
        => RenderFile("SupportTicketReceived.html", model);

    public string PlainTeamNotification(SupportEmailModel model) =>
        $"""
        New Mevora support ticket

        Ticket ID: {model.TicketId}
        Status: {model.Status}
        Priority: {model.Priority}
        Category: {model.Category}
        Subject: {model.Subject}
        From: {model.Name} <{model.Email}>
        User ID: {model.UserId}
        Created: {model.CreatedAt:u}

        Description:
        {model.Description}
        """;

    public string PlainUserConfirmation(SupportEmailModel model) =>
        $"""
        {model.SiteName} — Support request received

        Hello {model.Name},

        We received your support request.
        Ticket ID: {model.TicketId}
        Status: {model.Status}
        Subject: {model.Subject}

        Our team will review it as soon as possible.
        """;

    private string RenderFile(string fileName, SupportEmailModel model)
    {
        var path = Path.Combine(_env.ContentRootPath, "EmailTemplates", fileName);
        string template;
        if (File.Exists(path))
        {
            template = File.ReadAllText(path, Encoding.UTF8);
        }
        else
        {
            template = BuiltInFallback(fileName);
        }

        return Apply(template, model);
    }

    private static string Apply(string template, SupportEmailModel model) =>
        template
            .Replace("{{SiteName}}", Html(model.SiteName), StringComparison.Ordinal)
            .Replace("{{TicketId}}", Html(model.TicketId), StringComparison.Ordinal)
            .Replace("{{Name}}", Html(model.Name), StringComparison.Ordinal)
            .Replace("{{Email}}", Html(model.Email), StringComparison.Ordinal)
            .Replace("{{UserId}}", Html(model.UserId), StringComparison.Ordinal)
            .Replace("{{Category}}", Html(model.Category), StringComparison.Ordinal)
            .Replace("{{Subject}}", Html(model.Subject), StringComparison.Ordinal)
            .Replace("{{Description}}", Html(model.Description).Replace("\n", "<br/>", StringComparison.Ordinal), StringComparison.Ordinal)
            .Replace("{{Priority}}", Html(model.Priority), StringComparison.Ordinal)
            .Replace("{{Status}}", Html(model.Status), StringComparison.Ordinal)
            .Replace("{{CreatedAt}}", Html(model.CreatedAt.ToString("u")), StringComparison.Ordinal);

    private static string Html(string? value) => WebUtility.HtmlEncode(value ?? string.Empty);

    private static string BuiltInFallback(string fileName) =>
        fileName.Contains("Received", StringComparison.OrdinalIgnoreCase)
            ? """
              <html><body style="font-family:Manrope,Arial,sans-serif;color:#1f1f1f">
              <h2>{{SiteName}}</h2>
              <p>Support request received.</p>
              <p><strong>Ticket ID:</strong> {{TicketId}}<br/>
              <strong>Status:</strong> {{Status}}<br/>
              <strong>Subject:</strong> {{Subject}}</p>
              </body></html>
              """
            : """
              <html><body style="font-family:Manrope,Arial,sans-serif;color:#1f1f1f">
              <h2>New {{SiteName}} support ticket</h2>
              <p><strong>Ticket ID:</strong> {{TicketId}}<br/>
              <strong>Status:</strong> {{Status}}<br/>
              <strong>Priority:</strong> {{Priority}}<br/>
              <strong>Category:</strong> {{Category}}<br/>
              <strong>Subject:</strong> {{Subject}}<br/>
              <strong>From:</strong> {{Name}} &lt;{{Email}}&gt;<br/>
              <strong>User ID:</strong> {{UserId}}<br/>
              <strong>Created:</strong> {{CreatedAt}}</p>
              <p>{{Description}}</p>
              </body></html>
              """;
}
