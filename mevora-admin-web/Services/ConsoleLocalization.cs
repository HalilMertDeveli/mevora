using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Localization;
using Microsoft.Extensions.Localization;

namespace Mevora.Admin.Web.Services;

public static class ConsoleCultures
{
    public const string Turkish = "tr";
    public const string English = "en";
    public static readonly string[] All = [Turkish, English];

    public static bool IsSupported(string? culture) => culture is Turkish or English;
}

/// <summary>
/// Localisation helpers shared by pages and views. Everything here reads the
/// request culture (set by the language switcher's cookie), never the server's.
/// </summary>
public static class ConsoleLocalization
{
    /// <summary>
    /// A stored code shown in the reader's language: "code:X" in the table, else a
    /// readable form of X. A prefixed code ("staff.active") falls back to its bare
    /// form ("active") before the readable form.
    /// </summary>
    public static string Code(this IStringLocalizer l, string? code) => Lookup(key => l[key], code);

    public static string Code(this IHtmlLocalizer l, string? code) => Lookup(key => l.GetString(key), code);

    private static string Lookup(Func<string, LocalizedString> get, string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "—";
        var translated = get("code:" + code);
        if (!translated.ResourceNotFound) return translated.Value;
        var dot = code.IndexOf('.');
        if (dot <= 0 || dot == code.Length - 1) return JsonView.Label(code);
        var bare = code[(dot + 1)..];
        var inner = get("code:" + bare);
        return inner.ResourceNotFound ? JsonView.Label(bare) : inner.Value;
    }

    /// <summary>ISO timestamp → "29 Eyl 2026 14:05 UTC" / "29 Sep 2026 14:05 UTC".</summary>
    public static string When(this IHtmlLocalizer l, JsonElement e, string name)
    {
        var raw = e.Str(name);
        return raw is not null && DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)
            ? t.ToUniversalTime().ToString("dd MMM yyyy HH:mm", CultureInfo.CurrentCulture) + " UTC"
            : "—";
    }

    /// <summary>ISO timestamp → "3 sa önce" / "3 h ago".</summary>
    public static string Age(this IHtmlLocalizer l, JsonElement e, string name)
    {
        var raw = e.Str(name);
        if (raw is null || !DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)) return "—";
        var span = DateTimeOffset.UtcNow - t;
        if (span.TotalMinutes < 1) return l.GetString("just now").Value;
        if (span.TotalHours < 1) return l.GetString("{0} min ago", (int)span.TotalMinutes).Value;
        if (span.TotalDays < 1) return l.GetString("{0} h ago", (int)span.TotalHours).Value;
        return l.GetString("{0} d ago", (int)span.TotalDays).Value;
    }

    /// <summary>
    /// A safety-timeline event in the reader's language. The backend sends an
    /// English title plus a stable kind and detail; the kind picks the phrase
    /// and the detail's code (reason, action type, status) is translated too.
    /// </summary>
    public static string TimelineTitle(this IHtmlLocalizer l, JsonElement e)
    {
        var kind = e.Str("kind") ?? "";
        var detail = e.Get("detail");
        var phrase = l.GetString("timeline:" + kind);
        if (phrase.ResourceNotFound)
        {
            return e.S("title");
        }
        var title = e.Str("title") ?? "";
        var suffix = title.Contains(" — ", StringComparison.Ordinal) ? title[(title.IndexOf(" — ", StringComparison.Ordinal) + 3)..] : null;
        var code = kind switch
        {
            "report_received" => detail.Str("reason"),
            "moderation_action" => null,
            "photo_moderation" or "verification_status" => detail.Str("status"),
            "appeal_submitted" => detail.Str("actionType"),
            "case_opened" or "case_closed" or "support_ticket" => suffix,
            "appeal_resolved" => title.StartsWith("Appeal ", StringComparison.Ordinal) ? title["Appeal ".Length..] : null,
            _ => null,
        };
        if (kind == "moderation_action")
        {
            return l.Code(detail.Str("type"));
        }
        return code is { Length: > 0 } ? $"{phrase.Value} — {l.Code(code)}" : phrase.Value;
    }

    /// <summary>A domain error as a message in the reader's language, with its reference.</summary>
    public static string Error(this IStringLocalizer l, AdminApiException error)
    {
        var message = l[AdminErrorMessages.For(error.Code)].Value;
        return error.RequestId is { Length: > 0 } id
            ? $"{message} ({l["ref"].Value} {id[..Math.Min(12, id.Length)]})"
            : message;
    }

    public static string Error(this IStringLocalizer l, string code) => l[AdminErrorMessages.For(code)].Value;
}
