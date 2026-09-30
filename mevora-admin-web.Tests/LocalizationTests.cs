using System.Net;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Mevora.Admin.Web.Tests;

public sealed class LocalizationTests
{
    private const string CultureCookie = ".AspNetCore.Culture";

    [Fact]
    public async Task Console_defaults_to_Turkish()
    {
        using var factory = new AdminWebFactory {DefaultCulture = "tr"};
        var html = await factory.Client().GetStringAsync("/Login");
        Assert.Contains("<html lang=\"tr\"", html, StringComparison.Ordinal);
        Assert.Contains("Giriş yap", html, StringComparison.Ordinal);
        Assert.DoesNotContain(">Sign in<", html, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Configured_default_can_be_English()
    {
        using var factory = new AdminWebFactory {DefaultCulture = "en"};
        var html = await factory.Client().GetStringAsync("/Login");
        Assert.Contains("<html lang=\"en\"", html, StringComparison.Ordinal);
        Assert.Contains("Sign in", html, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Switcher_sets_the_culture_cookie_and_returns_to_the_page()
    {
        using var factory = new AdminWebFactory {DefaultCulture = "tr"};
        var client = factory.Client(AdminWebFactory.Moderator);
        factory.Api.Responses["adminGetDashboard"] = _ => AdminWebFactory.Json("{}");

        var response = await PostLanguage(client, "/Dashboard", "en", "/Dashboard?x=1");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/Dashboard?x=1", response.Headers.Location!.OriginalString);
        var cookie = response.Headers.GetValues("Set-Cookie").Single(c => c.StartsWith(CultureCookie, StringComparison.Ordinal));
        Assert.Contains("c%3Den%7Cuic%3Den", cookie, StringComparison.Ordinal);
        Assert.Contains("httponly", cookie, StringComparison.OrdinalIgnoreCase);

        var html = await client.GetStringAsync("/Dashboard");
        Assert.Contains("<html lang=\"en\"", html, StringComparison.Ordinal);
        Assert.Contains("Dashboard", html, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Switcher_is_available_before_sign_in()
    {
        using var factory = new AdminWebFactory {DefaultCulture = "tr", UseTestStaff = false};
        var client = factory.Client();

        var response = await PostLanguage(client, "/Login", "en", "/Login");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/Login", response.Headers.Location!.OriginalString);
        Assert.Contains("Sign in", await client.GetStringAsync("/Login"), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("https://evil.example/phish")]
    [InlineData("//evil.example")]
    [InlineData("/\\evil.example")]
    public async Task Switcher_never_redirects_off_site(string returnUrl)
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        var client = factory.Client();

        var response = await PostLanguage(client, "/Login", "tr", returnUrl);

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/", response.Headers.Location!.OriginalString);
    }

    [Fact]
    public async Task Unsupported_language_is_ignored()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        var client = factory.Client();

        var response = await PostLanguage(client, "/Login", "de", "/Login");

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.False(response.Headers.TryGetValues("Set-Cookie", out var cookies)
            && cookies.Any(c => c.StartsWith(CultureCookie, StringComparison.Ordinal)));
    }

    [Fact]
    public async Task Switcher_requires_antiforgery()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        var response = await factory.Client().PostAsync("/Language", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["culture"] = "en",
            ["returnUrl"] = "/Login",
        }));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Stored_codes_are_translated_for_display_only()
    {
        using var factory = new AdminWebFactory {DefaultCulture = "tr"};
        var client = factory.Client(AdminWebFactory.Moderator);
        factory.Api.Responses["adminListCases"] = _ => AdminWebFactory.Json("""
            {"items":[{"caseId":"case_1","type":"USER_REPORT","status":"open","priority":"high","summary":"s","createdAt":"2026-09-29T10:00:00Z"}],"nextCursor":null}
            """);

        var html = await client.GetStringAsync("/Cases");

        Assert.Contains("Kullanıcı raporu", html, StringComparison.Ordinal);
        Assert.Contains("Yüksek", html, StringComparison.Ordinal);
        // Filter values posted back to the backend stay the raw codes.
        Assert.Contains("value=\"USER_REPORT\"", html, StringComparison.Ordinal);
    }

    /// <summary>
    /// Every literal the console looks up must have a Turkish entry, or a Turkish
    /// reader would meet an English sentence. New text fails here until translated.
    /// </summary>
    [Fact]
    public void Every_console_string_has_a_Turkish_translation()
    {
        var project = FindProjectDirectory();
        var turkish = XDocument.Load(Path.Combine(project, "Resources", "SharedResource.tr.resx"))
            .Root!.Elements("data")
            .ToDictionary(d => (string)d.Attribute("name")!, d => (string)d.Element("value")!);

        var literal = new Regex("\\b[lL]\\[\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOptions.Compiled);
        var missing = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var file in Directory.EnumerateFiles(project, "*.*", SearchOption.AllDirectories)
                     .Where(f => (f.EndsWith(".cshtml", StringComparison.Ordinal) || f.EndsWith(".cs", StringComparison.Ordinal))
                                 && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                                 && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal)))
        {
            foreach (Match m in literal.Matches(File.ReadAllText(file)))
            {
                var key = m.Groups[1].Value.Replace("\\\"", "\"", StringComparison.Ordinal);
                if (!turkish.ContainsKey(key)) missing.Add($"{Path.GetFileName(file)}: {key}");
            }
        }

        Assert.True(missing.Count == 0, "Missing Turkish text:\n" + string.Join("\n", missing));
        foreach (var (key, value) in turkish)
        {
            Assert.False(string.IsNullOrWhiteSpace(value), "Empty Turkish text for " + key);
            Assert.Equal(Placeholders(key), Placeholders(value));
        }
    }

    private static string Placeholders(string s) =>
        string.Join(",", Regex.Matches(s, "\\{\\d+\\}").Select(m => m.Value).Order(StringComparer.Ordinal));

    private static string FindProjectDirectory()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "mevora-admin-web");
            if (File.Exists(Path.Combine(candidate, "Resources", "SharedResource.tr.resx"))) return candidate;
        }
        throw new InvalidOperationException("mevora-admin-web not found above " + AppContext.BaseDirectory);
    }

    private static async Task<HttpResponseMessage> PostLanguage(HttpClient client, string page, string culture, string returnUrl)
    {
        var token = await AdminWebFactory.AntiforgeryToken(client, page);
        return await client.PostAsync("/Language", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["culture"] = culture,
            ["returnUrl"] = returnUrl,
        }));
    }
}
