using System.Net;

namespace Mevora.Admin.Web.Tests;

/// <summary>
/// App Control page: read-only for Trust &amp; Safety admins, writable for the
/// owner, every form sends the revision it was rendered from, and local checks
/// catch obvious mistakes before the backend (which re-validates) is called.
/// </summary>
public sealed class AppControlTests
{
    private const string OwnerWithAppControl = "owner-1|super_admin|dashboard.read,app_control.read,app_control.write,audit.read";
    private const string TsaReadOnly = "tsa-1|trust_safety_admin|dashboard.read,app_control.read,audit.read";

    private static readonly string State = """
        {"config":{"revision":7,"updatedAt":"2026-09-30T08:00:00Z","updatedBy":"owner-1",
          "maintenance":{"enabled":false,"message":null},
          "minimumVersion":{"android":"1.0.0","ios":null},"recommendedVersion":{"android":null,"ios":null},"updateUrl":{"android":null,"ios":null},
          "features":{"boost":true,"calls":false,"spotify":true,"humorLab":true,"picks":true},
          "announcement":null},
         "health":{"backend":{"ok":true},"firestore":{"ok":true,"ms":12},"auth":{"ok":true,"ms":20},"storage":{"ok":false,"ms":30},
          "environment":"emulator","projectId":"mevora-d6ed0","checkedAt":"2026-09-30T10:00:00Z"}}
        """;

    private static AdminWebFactory Factory()
    {
        var f = new AdminWebFactory();
        f.Api.Responses["adminGetAppControl"] = _ => AdminWebFactory.Json(State);
        return f;
    }

    private static async Task<HttpResponseMessage> Post(AdminWebFactory f, string handler, Dictionary<string, string> form)
    {
        var client = f.Client(OwnerWithAppControl);
        form["__RequestVerificationToken"] = await AdminWebFactory.AntiforgeryToken(client, "/AppControl");
        return await client.PostAsync($"/AppControl?handler={handler}", new FormUrlEncodedContent(form));
    }

    [Fact]
    public async Task Roles_without_app_control_get_403_and_no_nav_entry()
    {
        using var f = Factory();
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(AdminWebFactory.Moderator).GetAsync("/AppControl")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await f.Client(AdminWebFactory.SupportAgent).GetAsync("/AppControl")).StatusCode);
        Assert.Empty(f.Api.Calls);
        var html = await f.Client(AdminWebFactory.Moderator).GetStringAsync("/Dashboard");
        Assert.DoesNotContain("href=\"/AppControl\"", html);
    }

    [Fact]
    public async Task Trust_and_safety_admin_sees_state_without_any_control()
    {
        using var f = Factory();
        var html = await f.Client(TsaReadOnly).GetStringAsync("/AppControl");
        Assert.Contains("Read-only", html);
        Assert.Contains("Video calls", html);
        Assert.DoesNotContain("handler=Maintenance", html);
        Assert.DoesNotContain("handler=Feature", html);
        Assert.DoesNotContain("handler=Version", html);
        Assert.DoesNotContain("handler=Announcement", html);
    }

    [Fact]
    public async Task Owner_sees_real_health_and_every_control()
    {
        using var f = Factory();
        var html = await f.Client(OwnerWithAppControl).GetStringAsync("/AppControl");
        Assert.Contains("Revision 7", html);
        Assert.Contains("Unreachable", html);
        Assert.Contains("href=\"/Audit?targetType=app_config\"", html);
        Assert.Contains("handler=Maintenance", html);
        Assert.Contains("handler=Feature", html);
        Assert.Contains("handler=Version", html);
        Assert.Contains("handler=Announcement", html);
        Assert.Contains("href=\"/AppControl\"", html);
    }

    [Fact]
    public async Task Maintenance_toggle_sends_the_rendered_revision()
    {
        using var f = Factory();
        var response = await Post(f, "Maintenance", new()
        {
            ["enabled"] = "true", ["message"] = "Birazdan buradayız.", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-maint",
        });
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var sent = f.Api.Last("adminUpdateMaintenanceMode");
        Assert.True(sent.GetProperty("enabled").GetBoolean());
        Assert.Equal(7, sent.GetProperty("expectedRevision").GetInt32());
        Assert.Equal("Birazdan buradayız.", sent.GetProperty("message").GetString());
    }

    [Fact]
    public async Task Feature_switch_needs_a_reason()
    {
        using var f = Factory();
        await Post(f, "Feature", new() {["feature"] = "boost", ["enabled"] = "false", ["reason"] = "", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-f"});
        Assert.False(f.Api.Called("adminUpdateFeatureSwitch"));
        await Post(f, "Feature", new() {["feature"] = "boost", ["enabled"] = "false", ["reason"] = "payment incident", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-f"});
        var sent = f.Api.Last("adminUpdateFeatureSwitch");
        Assert.Equal("boost", sent.GetProperty("feature").GetString());
        Assert.False(sent.GetProperty("enabled").GetBoolean());
    }

    [Fact]
    public async Task Unknown_feature_never_reaches_the_backend()
    {
        using var f = Factory();
        await Post(f, "Feature", new() {["feature"] = "chat", ["enabled"] = "false", ["reason"] = "x", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-f"});
        Assert.False(f.Api.Called("adminUpdateFeatureSwitch"));
    }

    [Theory]
    [InlineData("1.2", "https://evil.example.com/app")]
    [InlineData("latest", "")]
    [InlineData("1.2.0", "http://play.google.com/store/apps/details?id=x")]
    public async Task Version_rules_are_checked_locally(string min, string url)
    {
        using var f = Factory();
        await Post(f, "Version", new() {["platform"] = "android", ["minimumVersion"] = min, ["updateUrl"] = url, ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-v"});
        Assert.False(f.Api.Called("adminUpdateMinimumVersion"));
    }

    [Fact]
    public async Task Valid_version_rule_is_sent()
    {
        using var f = Factory();
        await Post(f, "Version", new()
        {
            ["platform"] = "ios", ["minimumVersion"] = "1.1.0", ["recommendedVersion"] = "1.2.0",
            ["updateUrl"] = "https://apps.apple.com/app/id123456", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-v",
        });
        var sent = f.Api.Last("adminUpdateMinimumVersion");
        Assert.Equal("ios", sent.GetProperty("platform").GetString());
        Assert.Equal("1.1.0", sent.GetProperty("minimumVersion").GetString());
    }

    [Fact]
    public async Task Announcement_rejects_markup_and_requires_an_end()
    {
        using var f = Factory();
        await Post(f, "Announcement", new() {["enabled"] = "true", ["title"] = "Hi", ["message"] = "<b>bold</b>", ["expiresAt"] = "2026-10-02T02:00", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-a"});
        await Post(f, "Announcement", new() {["enabled"] = "true", ["title"] = "Hi", ["message"] = "Tonight", ["expiresAt"] = "", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-a"});
        Assert.False(f.Api.Called("adminUpdateAnnouncement"));
    }

    [Fact]
    public async Task Announcement_times_are_sent_as_utc()
    {
        using var f = Factory();
        await Post(f, "Announcement", new()
        {
            ["enabled"] = "true", ["title"] = "Bakım", ["message"] = "Bu gece 02:00", ["severity"] = "warning",
            ["startsAt"] = "2026-10-01T20:00", ["expiresAt"] = "2026-10-02T03:00", ["expectedRevision"] = "7", ["idempotencyKey"] = "web-0123456789abcdef-a",
        });
        var sent = f.Api.Last("adminUpdateAnnouncement");
        Assert.Equal("2026-10-01T20:00:00Z", sent.GetProperty("startsAt").GetString());
        Assert.Equal("2026-10-02T03:00:00Z", sent.GetProperty("expiresAt").GetString());
        Assert.Equal("warning", sent.GetProperty("severity").GetString());
    }

    /// <summary>
    /// The console's audit filters are a copy of the backend vocabulary. Found
    /// in runtime QA: the App Control events were missing, so "History of App
    /// control changes" silently showed the whole log. Keep both in lock-step.
    /// </summary>
    [Fact]
    public void Audit_filter_vocabulary_matches_the_backend()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "functions", "src", "admin")))
        {
            dir = dir.Parent;
        }
        Assert.NotNull(dir);
        var ts = File.ReadAllText(Path.Combine(dir!.FullName, "functions", "src", "admin", "audit", "auditTypes.ts"));
        static string[] List(string source, string name)
        {
            var start = source.IndexOf($"export const {name} = [", StringComparison.Ordinal);
            var end = source.IndexOf("] as const", start, StringComparison.Ordinal);
            return System.Text.RegularExpressions.Regex.Matches(source[start..end], "\"([A-Za-z_]+)\"").Select(m => m.Groups[1].Value).ToArray();
        }
        Assert.Equal(List(ts, "AUDIT_ACTIONS").Order(), Mevora.Admin.Web.Services.Vocab.AuditActions.Order());
        Assert.Equal(List(ts, "AUDIT_TARGET_TYPES").Order(), Mevora.Admin.Web.Services.Vocab.AuditTargetTypes.Order());
    }

    [Fact]
    public async Task App_control_history_link_keeps_its_filter()
    {
        using var f = Factory();
        await f.Client(OwnerWithAppControl).GetStringAsync("/Audit?targetType=app_config&action=APP_MAINTENANCE_ENABLED");
        var sent = f.Api.Last("adminListAuditEvents");
        Assert.Equal("app_config", sent.GetProperty("targetType").GetString());
        Assert.Equal("APP_MAINTENANCE_ENABLED", sent.GetProperty("action").GetString());
    }

    [Fact]
    public async Task A_stale_revision_is_explained()
    {
        using var f = Factory();
        f.Api.Failures["adminUpdateMaintenanceMode"] = "conflict";
        // Same client: the flash message travels in its TempData cookie.
        var client = f.Client(OwnerWithAppControl);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/AppControl");
        var response = await client.PostAsync("/AppControl?handler=Maintenance", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["enabled"] = "true", ["expectedRevision"] = "6", ["idempotencyKey"] = "web-0123456789abcdef-m",
        }));
        var html = await client.GetStringAsync(response.Headers.Location!.OriginalString);
        Assert.Contains("Someone changed this at the same time", html);
    }
}
