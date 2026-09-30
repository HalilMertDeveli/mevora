using System.Globalization;
using System.Text.Json;

namespace Mevora.Admin.Web.Services;

/// <summary>
/// Read helpers over command results. Command responses are projections the
/// backend already shaped for the console; these helpers only make reading
/// them in Razor null-safe.
/// </summary>
public static class JsonView
{
    public static JsonElement Get(this JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) ? v : default;

    public static string? Str(this JsonElement e, string name)
    {
        var v = e.Get(name);
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString(),
            JsonValueKind.Number => v.GetRawText(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => null,
        };
    }

    public static string S(this JsonElement e, string name, string fallback = "—") => e.Str(name) is { Length: > 0 } s ? s : fallback;

    public static bool Bool(this JsonElement e, string name) => e.Get(name).ValueKind == JsonValueKind.True;

    public static long? Num(this JsonElement e, string name)
    {
        var v = e.Get(name);
        return v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) ? n : null;
    }

    public static IEnumerable<JsonElement> Arr(this JsonElement e, string name)
    {
        var v = e.Get(name);
        return v.ValueKind == JsonValueKind.Array ? v.EnumerateArray() : [];
    }

    public static IEnumerable<JsonElement> Items(this JsonElement e) => e.Arr("items");

    public static bool Has(this JsonElement e, string name) =>
        e.Get(name).ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null);

    /// <summary>ISO timestamp → "29 Sep 2026 14:05 UTC".</summary>
    public static string When(this JsonElement e, string name)
    {
        var raw = e.Str(name);
        return raw is not null && DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)
            ? t.ToUniversalTime().ToString("dd MMM yyyy HH:mm 'UTC'", CultureInfo.InvariantCulture)
            : "—";
    }

    /// <summary>ISO timestamp → "3 h ago" style age.</summary>
    public static string Age(this JsonElement e, string name)
    {
        var raw = e.Str(name);
        if (raw is null || !DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)) return "—";
        var span = DateTimeOffset.UtcNow - t;
        if (span.TotalMinutes < 1) return "just now";
        if (span.TotalHours < 1) return $"{(int)span.TotalMinutes} min ago";
        if (span.TotalDays < 1) return $"{(int)span.TotalHours} h ago";
        return $"{(int)span.TotalDays} d ago";
    }

    /// <summary>"USER_REPORT" / "manual_review" → "User report" / "Manual review".</summary>
    public static string Label(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "—";
        var words = code.Replace('_', ' ').Replace('.', ' ').ToLowerInvariant();
        return char.ToUpperInvariant(words[0]) + words[1..];
    }
}
