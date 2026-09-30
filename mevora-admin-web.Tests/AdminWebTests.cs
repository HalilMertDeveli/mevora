using System.Net;
using Mevora.Admin.Web.Configuration;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Tests;

public sealed class AccessTests
{
    [Fact]
    public async Task Unauthenticated_request_is_redirected_to_login()
    {
        using var factory = new AdminWebFactory();
        var response = await factory.Client().GetAsync("/Dashboard");
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.StartsWith("/Login", response.Headers.Location!.PathAndQuery.Replace("http://localhost", ""), StringComparison.Ordinal);
        Assert.Empty(factory.Api.Calls);
    }

    [Theory]
    [InlineData("/Users")]
    [InlineData("/Cases")]
    [InlineData("/Photos")]
    [InlineData("/Audit")]
    [InlineData("/Admin/Staff")]
    [InlineData("/Admin/Staff/tsa-1")]
    public async Task Every_console_page_requires_sign_in(string path)
    {
        using var factory = new AdminWebFactory();
        var response = await factory.Client().GetAsync(path);
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
    }

    [Fact]
    public async Task Login_page_is_public()
    {
        using var factory = new AdminWebFactory();
        var response = await factory.Client().GetAsync("/Login");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Theory]
    [InlineData("/Cases")]
    [InlineData("/Photos")]
    [InlineData("/Reports")]
    [InlineData("/Audit")]
    [InlineData("/Admin/Staff")]
    [InlineData("/Admin/Staff/tsa-1")]
    public async Task Role_without_the_permission_gets_403(string path)
    {
        using var factory = new AdminWebFactory();
        var response = await factory.Client(AdminWebFactory.SupportAgent).GetAsync(path);
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Empty(factory.Api.Calls);
    }

    [Fact]
    public async Task Dashboard_renders_only_the_counters_the_backend_returned()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetDashboard"] = _ => AdminWebFactory.Json("""
            {"counters":{"openCases":7,"criticalCases":2},"recentActions":[],"generatedAt":"2026-09-29T10:00:00Z"}
            """);
        var response = await factory.Client(AdminWebFactory.Moderator).GetAsync("/Dashboard");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var html = await response.Content.ReadAsStringAsync();
        Assert.Contains("Critical cases", html);
        Assert.DoesNotContain("Urgent support tickets", html);
        // Navigation reflects permissions (the server still enforces them).
        Assert.DoesNotContain("href=\"/Admin/Staff\"", html);
        Assert.Contains("href=\"/Cases\"", html);
    }

    [Fact]
    public async Task User_page_needs_user_read()
    {
        using var factory = new AdminWebFactory();
        var noRead = factory.Client("x|moderator|dashboard.read");
        Assert.Equal(HttpStatusCode.Forbidden, (await noRead.GetAsync("/Users/u1")).StatusCode);
        var ok = await factory.Client(AdminWebFactory.Moderator).GetAsync("/Users/u1");
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Assert.True(factory.Api.Called("adminGetUserOverview"));
    }

    [Fact]
    public async Task Actions_a_role_lacks_are_not_offered()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetUserOverview"] = _ => AdminWebFactory.Json("""{"account":{"accountStatus":"active","displayName":"Ada"},"auth":{},"profile":{},"verification":{},"safety":{},"subscription":{}}""");
        var moderatorHtml = await factory.Client(AdminWebFactory.Moderator).GetStringAsync("/Users/u1");
        Assert.Contains("Suspend temporarily", moderatorHtml);
        Assert.DoesNotContain("Ban permanently", moderatorHtml);
        var seniorHtml = await factory.Client(AdminWebFactory.Senior).GetStringAsync("/Users/u1");
        Assert.Contains("Ban permanently", seniorHtml);
        Assert.DoesNotContain("Mark verified", seniorHtml, StringComparison.OrdinalIgnoreCase);
    }
}

public sealed class FormSafetyTests
{
    [Fact]
    public async Task Post_without_antiforgery_token_is_rejected()
    {
        using var factory = new AdminWebFactory();
        var client = factory.Client(AdminWebFactory.Senior);
        var response = await client.PostAsync("/Users/u1?handler=Ban", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["reasonCode"] = "SPAM",
            ["internalNote"] = "x",
            ["confirmWord"] = "BAN",
            ["idempotencyKey"] = "web-abcdef123456",
        }));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.False(factory.Api.Called("adminBanUser"));
    }

    [Fact]
    public async Task Ban_requires_typed_confirmation_and_a_note_before_anything_is_sent()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetUserOverview"] = _ => AdminWebFactory.Json("""{"account":{"accountStatus":"active"}}""");
        var client = factory.Client(AdminWebFactory.Senior);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Users/u1");
        async Task<HttpResponseMessage> Post(string confirm, string note) =>
            await client.PostAsync("/Users/u1?handler=Ban", new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["__RequestVerificationToken"] = token,
                ["reasonCode"] = "SCAM_FRAUD",
                ["internalNote"] = note,
                ["confirmWord"] = confirm,
                ["idempotencyKey"] = "web-0123456789abcdef",
            }));
        Assert.Equal(HttpStatusCode.Redirect, (await Post("ban", "reason")).StatusCode);
        Assert.Equal(HttpStatusCode.Redirect, (await Post("BAN", "   ")).StatusCode);
        Assert.False(factory.Api.Called("adminBanUser"));

        var ok = await Post("BAN", "confirmed scam ring");
        Assert.Equal(HttpStatusCode.Redirect, ok.StatusCode);
        var sent = factory.Api.Last("adminBanUser");
        Assert.Equal("u1", sent.GetProperty("uid").GetString());
        Assert.Equal("SCAM_FRAUD", sent.GetProperty("reasonCode").GetString());
        Assert.Equal("web-0123456789abcdef", sent.GetProperty("idempotencyKey").GetString());
    }

    [Theory]
    [InlineData("custom", "0")]
    [InlineData("custom", "9000")]
    [InlineData("custom", "")]
    [InlineData("5", "")]
    public async Task Invalid_suspension_lengths_never_reach_the_backend(string duration, string custom)
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetUserOverview"] = _ => AdminWebFactory.Json("""{"account":{"accountStatus":"active"}}""");
        var client = factory.Client(AdminWebFactory.Moderator);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Users/u1");
        await client.PostAsync("/Users/u1?handler=Suspend", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["reasonCode"] = "SPAM",
            ["duration"] = duration,
            ["customHours"] = custom,
            ["internalNote"] = "note",
            ["idempotencyKey"] = "web-0123456789abcdef",
        }));
        Assert.False(factory.Api.Called("adminSuspendUser"));
    }

    [Fact]
    public async Task A_preset_suspension_is_sent_with_its_hours()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetUserOverview"] = _ => AdminWebFactory.Json("""{"account":{"accountStatus":"active"}}""");
        var client = factory.Client(AdminWebFactory.Moderator);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Users/u1");
        await client.PostAsync("/Users/u1?handler=Suspend", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["reasonCode"] = "HARASSMENT",
            ["duration"] = "168",
            ["internalNote"] = "three reports",
            ["idempotencyKey"] = "web-0123456789abcdef",
        }));
        Assert.Equal(168, factory.Api.Last("adminSuspendUser").GetProperty("durationHours").GetInt32());
    }

    [Fact]
    public async Task Photo_reject_without_a_reason_is_refused_locally()
    {
        using var factory = new AdminWebFactory();
        var client = factory.Client(AdminWebFactory.Moderator);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Photos?filter=manual_review");
        await client.PostAsync("/Photos?handler=Decide", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["uid"] = "u1",
            ["imageId"] = "img1",
            ["decision"] = "reject",
            ["reasonCode"] = "",
            ["idempotencyKey"] = "web-0123456789abcdef",
        }));
        Assert.False(factory.Api.Called("adminReviewPhoto"));
    }
}

public sealed class BackendIntegrationTests
{
    [Fact]
    public async Task Pagination_passes_the_cursor_and_renders_the_next_link()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminListCases"] = _ => AdminWebFactory.Json("""
            {"items":[{"caseId":"case_1","type":"USER_REPORT","status":"open","priority":"high","sourceCount":1,"reporterCount":1,"createdAt":"2026-09-29T09:00:00Z"}],"nextCursor":"CURSOR_NEXT"}
            """);
        var html = await factory.Client(AdminWebFactory.Moderator).GetStringAsync("/Cases?cursor=CURSOR_ONE");
        Assert.Equal("CURSOR_ONE", factory.Api.Last("adminListCases").GetProperty("cursor").GetString());
        Assert.Contains("cursor=CURSOR_NEXT", html);
        Assert.Contains("case_1", html);
    }

    [Fact]
    public async Task Domain_errors_become_readable_messages_not_exceptions()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Failures["adminAssignCase"] = "case_already_assigned";
        factory.Api.Responses["adminGetCase"] = _ => AdminWebFactory.Json("""{"caseId":"case_1","type":"USER_REPORT","status":"open","priority":"high"}""");
        var client = factory.Client(AdminWebFactory.Moderator);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Cases/case_1");
        var post = await client.PostAsync("/Cases/case_1?handler=Claim", new FormUrlEncodedContent(new Dictionary<string, string> {["__RequestVerificationToken"] = token}));
        Assert.Equal(HttpStatusCode.Redirect, post.StatusCode);
        var html = await client.GetStringAsync("/Cases/case_1");
        Assert.Contains(AdminErrorMessages.For("case_already_assigned"), html);
        Assert.DoesNotContain("AdminApiException", html);
        Assert.DoesNotContain("StackTrace", html, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task A_load_error_is_shown_as_a_banner()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Failures["adminListReports"] = "internal_error";
        var response = await factory.Client(AdminWebFactory.Moderator).GetAsync("/Reports");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains(AdminErrorMessages.For("internal_error"), await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task A_revoked_session_is_ended_and_sent_to_login()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Failures["adminGetDashboard"] = "session_revoked";
        var response = await factory.Client(AdminWebFactory.Moderator).GetAsync("/Dashboard");
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Contains("/Login?reason=expired", response.Headers.Location!.ToString());
    }

    [Fact]
    public async Task Photo_preview_is_served_from_the_backend_and_never_cached()
    {
        using var factory = new AdminWebFactory();
        factory.Api.Responses["adminGetPhotoPreview"] = _ => AdminWebFactory.Json("""{"contentType":"image/png","dataBase64":"iVBORw0KGgo="}""");
        var response = await factory.Client(AdminWebFactory.Moderator).GetAsync("/Photos?handler=Preview&uid=u1&imageId=img1");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("image/png", response.Content.Headers.ContentType!.MediaType);
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
    }

    [Fact]
    public async Task There_is_no_chat_reading_page()
    {
        using var factory = new AdminWebFactory();
        foreach (var path in new[] {"/Chats", "/Messages", "/Users/u1/Messages", "/Conversations"})
        {
            var response = await factory.Client(AdminWebFactory.Senior).GetAsync(path);
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }
    }
}

public sealed class SecurityTests
{
    [Fact]
    public async Task Security_headers_are_strict()
    {
        using var factory = new AdminWebFactory();
        var response = await factory.Client().GetAsync("/Login");
        var csp = response.Headers.GetValues("Content-Security-Policy").Single();
        Assert.Contains("default-src 'none'", csp);
        Assert.Contains("script-src 'self'", csp);
        Assert.Contains("frame-ancestors 'none'", csp);
        Assert.DoesNotContain("unsafe-inline", csp);
        Assert.DoesNotContain("unsafe-eval", csp);
        Assert.Equal("DENY", response.Headers.GetValues("X-Frame-Options").Single());
        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
        Assert.Equal("no-referrer", response.Headers.GetValues("Referrer-Policy").Single());
        Assert.Contains("no-store", response.Headers.CacheControl!.ToString());
    }

    [Theory]
    [InlineData("/Login")]
    [InlineData("/Dashboard")]
    [InlineData("/Users/u1")]
    [InlineData("/Cases")]
    public async Task No_secret_or_credential_is_ever_rendered(string path)
    {
        using var factory = new AdminWebFactory();
        var client = path == "/Login" ? factory.Client() : factory.Client(AdminWebFactory.Senior);
        var html = await client.GetStringAsync(path);
        Assert.DoesNotContain(AdminWebFactory.Secret, html);
        Assert.DoesNotContain("private_key", html);
        Assert.DoesNotContain("service_account", html, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("header.payload.sig", html);
        Assert.DoesNotContain("refresh-token", html);
        Assert.DoesNotContain("<script>", html);
    }

    [Fact]
    public void The_admin_web_references_no_server_credential_library()
    {
        var csproj = File.ReadAllText(Path.Combine(FindRepoRoot(), "mevora-admin-web", "Mevora.Admin.Web.csproj"));
        Assert.DoesNotContain("PackageReference Include=\"FirebaseAdmin\"", csproj);
        Assert.DoesNotContain("PackageReference Include=\"Google.Cloud.Firestore\"", csproj);
    }

    [Fact]
    public void Production_configuration_refuses_emulator_shortcuts()
    {
        var options = new AdminWebOptions
        {
            ProjectId = "p",
            WebApiKey = "k",
            FunctionsBaseUrl = "http://127.0.0.1:5001/p/europe-west1",
            BffSharedSecret = AdminWebOptions.EmulatorDevBffSecret,
            AuthEmulatorHost = "127.0.0.1:9099",
        };
        var errors = options.Validate(isDevelopment: false).ToList();
        Assert.Contains(errors, e => e.Contains("AuthEmulatorHost"));
        Assert.Contains(errors, e => e.Contains("emulator BFF secret"));
        Assert.Contains(errors, e => e.Contains("https"));
        Assert.Empty(options.Validate(isDevelopment: true));
    }

    [Fact]
    public void An_unset_bff_secret_fails_validation_everywhere()
    {
        var options = new AdminWebOptions {ProjectId = "p", WebApiKey = "k", FunctionsBaseUrl = "https://x"};
        Assert.Contains(options.Validate(true), e => e.Contains("BffSharedSecret"));
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "mevora-admin-web")))
        {
            dir = dir.Parent;
        }
        return dir?.FullName ?? throw new InvalidOperationException("repo root not found");
    }
}

public sealed class LoginTests
{
    private static FormUrlEncodedContent Form(string token, params (string, string)[] fields)
    {
        var dict = fields.ToDictionary(f => f.Item1, f => f.Item2);
        dict["__RequestVerificationToken"] = token;
        return new FormUrlEncodedContent(dict);
    }

    [Fact]
    public async Task A_member_account_is_refused_with_a_generic_message()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        factory.Identity.Next = new PasswordSignInResult.Success(FakeIdentity.Tokens());
        factory.Api.Failures["adminRecordLogin"] = "staff_inactive";
        var client = factory.Client();
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Login");
        var response = await client.PostAsync("/Login?handler=Password", Form(token, ("Email", "member@example.com"), ("Password", "secret")));
        var html = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("does not have access", html);
        Assert.False(response.Headers.TryGetValues("Set-Cookie", out var cookies) && cookies.Any(c => c.StartsWith("mevora-admin=", StringComparison.Ordinal)));
    }

    [Fact]
    public async Task Staff_sign_in_creates_a_server_side_session()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        factory.Identity.Next = new PasswordSignInResult.Success(FakeIdentity.Tokens());
        factory.Api.Responses["adminRecordLogin"] = _ => AdminWebFactory.Json("""{"uid":"staff-1","role":"moderator","displayName":"Mo","permissions":["dashboard.read","case.read"],"mfa":true}""");
        factory.Api.Responses["adminGetDashboard"] = _ => AdminWebFactory.Json("""{"counters":{},"recentActions":[]}""");
        var client = factory.Client();
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Login");
        var response = await client.PostAsync("/Login?handler=Password", Form(token, ("Email", "mo@mevora.test"), ("Password", "secret")));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/Dashboard", response.Headers.Location!.ToString());
        var cookie = response.Headers.GetValues("Set-Cookie").First(c => c.StartsWith("mevora-admin=", StringComparison.Ordinal));
        Assert.Contains("httponly", cookie, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("samesite=strict", cookie, StringComparison.OrdinalIgnoreCase);
        // The cookie is a pointer to a server-side ticket, not the tokens.
        Assert.DoesNotContain("header.payload.sig", cookie);
        var dashboard = await client.GetAsync("/Dashboard");
        Assert.Equal(HttpStatusCode.OK, dashboard.StatusCode);
    }

    [Fact]
    public async Task A_staff_account_without_mfa_must_enroll_before_any_access()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        factory.Identity.Next = new PasswordSignInResult.Success(FakeIdentity.Tokens());
        factory.Api.Failures["adminRecordLogin"] = "mfa_required";
        var client = factory.Client();
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Login");
        var response = await client.PostAsync("/Login?handler=Password", Form(token, ("Email", "mo@mevora.test"), ("Password", "secret")));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var html = await client.GetStringAsync("/Login");
        Assert.Contains("Two-factor authentication is required", html);
        Assert.Contains("JBSWY3DPEHPK3PXP", html);
        Assert.Equal(HttpStatusCode.Redirect, (await client.GetAsync("/Dashboard")).StatusCode);
    }

    [Fact]
    public async Task Enrolled_staff_are_asked_for_their_code()
    {
        using var factory = new AdminWebFactory {UseTestStaff = false};
        factory.Identity.Next = new PasswordSignInResult.SecondFactorRequired("pending", [new MfaEnrollment("enr-1", "Phone app", true)]);
        var client = factory.Client();
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Login");
        await client.PostAsync("/Login?handler=Password", Form(token, ("Email", "mo@mevora.test"), ("Password", "secret")));
        var html = await client.GetStringAsync("/Login");
        Assert.Contains("Verification code", html);
        token = await AdminWebFactory.AntiforgeryToken(client, "/Login");
        var wrong = await client.PostAsync("/Login?handler=Code", Form(token, ("Code", "000000")));
        Assert.Contains("did not work", await wrong.Content.ReadAsStringAsync());
    }
}
