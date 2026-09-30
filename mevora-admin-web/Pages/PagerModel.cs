namespace Mevora.Admin.Web.Pages;

/// <summary>Cursor pagination link: keeps the current filters, swaps the cursor.</summary>
public sealed record PagerModel(string Path, string? NextCursor, IReadOnlyDictionary<string, string?> RouteValues, bool HasPrevious);
