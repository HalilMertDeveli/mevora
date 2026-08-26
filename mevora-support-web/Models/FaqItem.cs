namespace Mevora.Web.Models;

public sealed class FaqItem
{
    public string Id { get; set; } = string.Empty;
    public string Question { get; set; } = string.Empty;
    public string Answer { get; set; } = string.Empty;
    public string Category { get; set; } = "general";
    public int Order { get; set; }
    public bool IsPublished { get; set; } = true;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
