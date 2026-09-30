using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace Mevora.Admin.Web.Pages.AppControl;

/// <summary>
/// App Control: the owner's switches for the mobile app. Four named changes
/// (maintenance, versions, feature switches, announcement), never a config
/// editor. Every form carries the revision it was rendered from, so a change
/// made on a stale page is refused instead of overwriting someone else's.
/// Trust &amp; Safety admins see the page read-only.
///
/// The checks here only give faster, clearer messages; the backend validates
/// every value again and is the authority.
/// </summary>
[RequirePermission("app_control.read")]
public sealed partial class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public JsonElement Data { get; private set; }

    public JsonElement Config => Data.Get("config");

    public JsonElement Health => Data.Get("health");

    public string FormKey { get; } = NewKey();

    public bool CanWrite => Can("app_control.write");

    public const int TitleMax = 80;
    public const int MessageMax = 280;

    /// <summary>The features that can be switched off, what switching off does, and what it never touches.</summary>
    public static readonly (string Key, string Label, string Effect)[] Features =
    [
        ("boost", "Boost", "Members cannot start a Boost. Boosts already bought are still credited."),
        ("calls", "Video calls", "Members cannot start a call. Chat is unaffected."),
        ("spotify", "Spotify music", "Connecting and syncing Spotify pause. Signing in with Spotify keeps working."),
        ("humorLab", "Humor Lab", "The Humor Lab feed and the daily humor tour are hidden."),
        ("picks", "Mevora Picks", "The Picks section in Discover is hidden."),
    ];

    [GeneratedRegex(@"^\d{1,4}(\.\d{1,4}){0,3}$")]
    private static partial Regex VersionPattern();

    private static readonly string[] StoreHosts = ["play.google.com", "apps.apple.com", "itunes.apple.com"];

    public async Task OnGetAsync()
    {
        Data = await Load("adminGetAppControl") ?? default;
    }

    private static bool LooksLikeMarkup(string? value) => value is not null && (value.Contains('<') || value.Contains('>'));

    /// <summary>"2026-10-01T02:00" from a datetime-local input, read as UTC → ISO 8601.</summary>
    private static string? UtcInstant(string? value) =>
        value is { Length: > 0 } && DateTime.TryParseExact(value, ["yyyy-MM-ddTHH:mm", "yyyy-MM-ddTHH:mm:ss"], CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var t)
            ? t.ToString("yyyy-MM-ddTHH:mm:ss'Z'", CultureInfo.InvariantCulture)
            : null;

    public Task<IActionResult> OnPostMaintenanceAsync(bool enabled, string? message, int expectedRevision, string? idempotencyKey)
    {
        var m = Clean(message, MessageMax + 1);
        if (m is { Length: > MessageMax }) return Task.FromResult(Invalid($"The maintenance message can be at most {MessageMax} characters."));
        if (LooksLikeMarkup(m)) return Task.FromResult(Invalid("Plain text only: remove < and >."));
        return Act("adminUpdateMaintenanceMode", new {enabled, message = enabled ? m : null, expectedRevision, idempotencyKey},
            enabled ? "Maintenance is ON. The app shows the maintenance screen within seconds." : "Maintenance is OFF. The app returns to normal.");
    }

    public Task<IActionResult> OnPostVersionAsync(string? platform, string? minimumVersion, string? recommendedVersion, string? updateUrl,
        int expectedRevision, string? idempotencyKey)
    {
        if (platform is not ("android" or "ios")) return Task.FromResult(Invalid("Choose Android or iOS."));
        var min = Clean(minimumVersion, 20);
        var rec = Clean(recommendedVersion, 20);
        var url = Clean(updateUrl, 300);
        if ((min is not null && !VersionPattern().IsMatch(min)) || (rec is not null && !VersionPattern().IsMatch(rec)))
        {
            return Task.FromResult(Invalid("Versions look like 1.4.0."));
        }
        if (url is not null && (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "https" || !StoreHosts.Contains(uri.Host)))
        {
            return Task.FromResult(Invalid("The update link must be the app's Google Play or App Store page (https)."));
        }
        return Act("adminUpdateMinimumVersion", new {platform, minimumVersion = min, recommendedVersion = rec, updateUrl = url, expectedRevision, idempotencyKey},
            $"{(platform == "ios" ? "iOS" : "Android")} version rules saved.");
    }

    public Task<IActionResult> OnPostFeatureAsync(string? feature, bool enabled, string? reason, int expectedRevision, string? idempotencyKey)
    {
        var f = Features.FirstOrDefault(x => x.Key == feature);
        if (f.Key is null) return Task.FromResult(Invalid("Unknown feature."));
        var r = Clean(reason, 500);
        if (r is null) return Task.FromResult(Invalid("Give a reason; it is kept in the audit log."));
        return Act("adminUpdateFeatureSwitch", new {feature, enabled, reason = r, expectedRevision, idempotencyKey},
            $"{f.Label} is now {(enabled ? "ON" : "OFF")}. The backend enforces it immediately; the app updates within seconds.");
    }

    public Task<IActionResult> OnPostAnnouncementAsync(bool enabled, string? title, string? message, string? severity, string? startsAt,
        string? expiresAt, int expectedRevision, string? idempotencyKey)
    {
        if (!enabled)
        {
            return Act("adminUpdateAnnouncement", new {enabled = false, expectedRevision, idempotencyKey}, "Announcement turned off.");
        }
        var t = Clean(title, TitleMax + 1);
        var m = Clean(message, MessageMax + 1);
        if (t is null || m is null) return Task.FromResult(Invalid("An announcement needs a title and a message."));
        if (t.Length > TitleMax || m.Length > MessageMax) return Task.FromResult(Invalid($"Title up to {TitleMax} and message up to {MessageMax} characters."));
        if (LooksLikeMarkup(t) || LooksLikeMarkup(m)) return Task.FromResult(Invalid("Plain text only: remove < and >."));
        var ends = UtcInstant(expiresAt);
        if (ends is null) return Task.FromResult(Invalid("Choose when the announcement ends (UTC, at most 31 days)."));
        var starts = UtcInstant(startsAt);
        return Act("adminUpdateAnnouncement", new
        {
            enabled = true,
            title = t,
            message = m,
            severity = severity == "warning" ? "warning" : "info",
            startsAt = starts,
            expiresAt = ends,
            expectedRevision,
            idempotencyKey,
        }, "Announcement published. The app shows it from its start time until it ends.");
    }
}
