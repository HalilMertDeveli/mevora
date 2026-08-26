namespace Mevora.Web.Models;

public sealed class SupportTicket
{
    public string Id { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Subject { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Priority { get; set; } = SupportPriorities.Normal;
    public string Status { get; set; } = SupportTicketStatuses.Open;
    public string? AttachmentUrl { get; set; }
    public IReadOnlyList<string> Attachments { get; set; } = [];
    public string Source { get; set; } = "website";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
