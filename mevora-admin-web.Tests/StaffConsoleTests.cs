using System.Net;

namespace Mevora.Admin.Web.Tests;

/// <summary>
/// Owner staff console: list, add (no password ever shown), detail controls,
/// owner protection in the UI, combined audit filters and the owner dashboard.
/// Authority stays with the backend; these tests pin what the console sends
/// and what it refuses to offer.
/// </summary>
public sealed class StaffConsoleTests
{
    private static readonly string StaffList = """
        {"items":[
          {"uid":"owner-1","role":"super_admin","status":"active","isOwner":true,"displayName":"Halil (Owner)","email":"owner@example.com","createdAt":"2026-09-01T10:00:00Z","createdBy":"bootstrap","lastLoginAt":"2026-09-30T08:00:00Z","lastLoginMfa":true,"qaSeed":false},
          {"uid":"tsa-1","role":"trust_safety_admin","status":"active","isOwner":false,"displayName":"QA Tolga","email":"tsa@mevora.test","createdAt":"2026-09-02T10:00:00Z","createdBy":"seed","lastLoginAt":null,"qaSeed":true},
          {"uid":"mod-9","role":"moderator","status":"disabled","isOwner":false,"displayName":"Former Mod","email":"m@example.com","createdAt":"2026-09-03T10:00:00Z","createdBy":"owner-1","qaSeed":false}
        ],"summary":{"active":2,"disabled":1}}
        """;

    private static string Detail(string uid, bool owner = false, string status = "active") => $$"""
        {"staff":{"uid":"{{uid}}","role":"trust_safety_admin","status":"{{status}}","isOwner":{{(owner ? "true" : "false")}},"displayName":"Colleague","email":"c@example.com","createdAt":"2026-09-02T10:00:00Z","createdBy":"owner-1","lastRoleChangeAt":"2026-09-02T10:00:00Z","lastLoginAt":"2026-09-30T08:00:00Z","lastLoginMfa":true,"qaSeed":false},
         "account":{"exists":true,"disabled":false,"emailVerified":true,"createdAt":"2026-09-02T10:00:00Z","lastSignInAt":"2026-09-30T08:00:00Z","mfaFactors":["totp"]},
         "activity":{"casesResolved":4,"reportsResolved":2,"photosReviewed":9,"usersWarned":1,"usersSuspended":3,"usersBanned":1,"usersRestored":0,"supportReplies":7,"supportResolved":5,"appealsResolved":2,"verificationActions":0},
         "recentActions":[{"eventId":"e1","action":"USER_BANNED","targetType":"user","targetId":"member-7","caseId":null,"createdAt":"2026-09-30T09:00:00Z"}],
         "lastActivityAt":"2026-09-30T09:00:00Z"}
        """;

    [Fact]
    public async Task Staff_list_marks_the_owner_and_qa_identities()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminListStaff"] = _ => AdminWebFactory.Json(StaffList);
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Admin/Staff");
        Assert.Contains("Halil (Owner)", html);
        Assert.Contains(">Owner</span>", html);
        Assert.Contains("QA · emulator only", html);
        Assert.Contains("href=\"/Admin/Staff/tsa-1\"", html);
        Assert.Contains("2 active · 1 disabled", html);
    }

    [Fact]
    public async Task Add_staff_never_offers_super_admin_or_a_password_field()
    {
        using var f = new AdminWebFactory();
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Admin/Staff");
        Assert.Contains("Add staff", html);
        Assert.Contains("value=\"trust_safety_admin\"", html);
        Assert.DoesNotContain("value=\"super_admin\"", html);
        Assert.DoesNotContain("type=\"password\"", html);
    }

    [Fact]
    public async Task Adding_a_colleague_creates_them_and_asks_firebase_to_email_the_setup_link()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminCreateStaff"] = _ => AdminWebFactory.Json("""{"uid":"new-1","email":"new@example.com","role":"trust_safety_admin","accountCreated":true,"replay":false}""");
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff");
        var response = await client.PostAsync("/Admin/Staff?handler=Create", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["email"] = "New@Example.com",
            ["displayName"] = "New Colleague",
            ["role"] = "trust_safety_admin",
            ["idempotencyKey"] = "web-0123456789abcdef-create",
        }));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/Admin/Staff/new-1", response.Headers.Location!.OriginalString);
        var sent = f.Api.Last("adminCreateStaff");
        Assert.Equal("trust_safety_admin", sent.GetProperty("role").GetString());
        Assert.Equal("web-0123456789abcdef-create", sent.GetProperty("idempotencyKey").GetString());
        Assert.False(sent.TryGetProperty("password", out _));
        Assert.Equal(["new@example.com"], f.Identity.SetupEmails.ToArray());
    }

    [Fact]
    public async Task An_existing_login_gets_no_setup_email()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminCreateStaff"] = _ => AdminWebFactory.Json("""{"uid":"w-1","email":"w@example.com","role":"support_agent","accountCreated":false,"replay":false}""");
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff");
        await client.PostAsync("/Admin/Staff?handler=Create", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["email"] = "w@example.com", ["displayName"] = "Worker", ["role"] = "support_agent", ["idempotencyKey"] = "web-0123456789abcdef-create",
        }));
        Assert.Empty(f.Identity.SetupEmails);
    }

    [Fact]
    public async Task Super_admin_is_rejected_locally_before_the_backend_is_called()
    {
        using var f = new AdminWebFactory();
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff");
        var response = await client.PostAsync("/Admin/Staff?handler=Create", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["email"] = "x@example.com", ["displayName"] = "X Y", ["role"] = "super_admin", ["idempotencyKey"] = "web-0123456789abcdef-create",
        }));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.False(f.Api.Called("adminCreateStaff"));
    }

    [Fact]
    public async Task Backend_refusal_is_shown_as_a_message()
    {
        using var f = new AdminWebFactory();
        f.Api.Failures["adminCreateStaff"] = "staff_account_is_member";
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff");
        var response = await client.PostAsync("/Admin/Staff?handler=Create", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["email"] = "member@example.com", ["displayName"] = "Member", ["role"] = "moderator", ["idempotencyKey"] = "web-0123456789abcdef-create",
        }));
        var html = await client.GetStringAsync(response.Headers.Location!.OriginalString);
        Assert.Contains("Staff need a dedicated work email", html);
        Assert.Empty(f.Identity.SetupEmails);
    }

    [Fact]
    public async Task Trust_and_safety_admin_cannot_open_staff_management()
    {
        using var f = new AdminWebFactory();
        var client = f.Client(AdminWebFactory.TrustSafetyAdmin);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/Admin/Staff")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/Admin/Staff/mod-1")).StatusCode);
        Assert.Empty(f.Api.Calls);
        var nav = await client.GetStringAsync("/Dashboard");
        Assert.DoesNotContain("href=\"/Admin/Staff\"", nav);
    }

    [Fact]
    public async Task Staff_detail_shows_activity_and_every_control()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("tsa-1"));
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Admin/Staff/tsa-1");
        Assert.Equal("tsa-1", f.Api.Last("adminGetStaff").GetProperty("targetUid").GetString());
        Assert.Contains("Users suspended", html);
        Assert.Contains("Enrolled: totp", html);
        Assert.Contains("USER_BANNED", html);
        Assert.Contains("handler=Role", html);
        Assert.Contains("handler=Revoke", html);
        Assert.Contains("handler=Disable", html);
        Assert.Contains("handler=Activation", html);
        Assert.Contains("href=\"/Audit?actor=tsa-1\"", html);
        Assert.DoesNotContain("value=\"super_admin\"", html);
    }

    [Fact]
    public async Task The_owner_record_offers_no_controls()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("owner-2", owner: true));
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Admin/Staff/owner-2");
        Assert.Contains("owner's account is protected", html);
        Assert.DoesNotContain("handler=Disable", html);
        Assert.DoesNotContain("handler=Role", html);
        Assert.DoesNotContain("handler=Revoke", html);
    }

    [Fact]
    public async Task Your_own_record_offers_no_controls()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("owner-1"));
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Admin/Staff/owner-1");
        Assert.Contains("This is your own account", html);
        Assert.DoesNotContain("handler=Disable", html);
    }

    [Theory]
    [InlineData("Revoke", "adminRevokeStaffSessions")]
    [InlineData("Disable", "adminDisableStaff")]
    public async Task Detail_controls_send_the_matching_command(string handler, string command)
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("tsa-1"));
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff/tsa-1");
        var response = await client.PostAsync($"/Admin/Staff/tsa-1?handler={handler}", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["reason"] = "lost laptop",
        }));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var sent = f.Api.Last(command);
        Assert.Equal("tsa-1", sent.GetProperty("targetUid").GetString());
        Assert.Equal("lost laptop", sent.GetProperty("reason").GetString());
    }

    [Fact]
    public async Task Role_change_refuses_super_admin_locally()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("tsa-1"));
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff/tsa-1");
        await client.PostAsync("/Admin/Staff/tsa-1?handler=Role", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token, ["role"] = "super_admin",
        }));
        Assert.False(f.Api.Called("adminUpdateStaffRole"));
    }

    [Fact]
    public async Task Resending_the_setup_email_is_authorised_by_the_backend_first()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetStaff"] = _ => AdminWebFactory.Json(Detail("tsa-1"));
        f.Api.Responses["adminIssueStaffActivation"] = _ => AdminWebFactory.Json("""{"uid":"tsa-1","email":"c@example.com"}""");
        var client = f.Client(AdminWebFactory.Owner);
        var token = await AdminWebFactory.AntiforgeryToken(client, "/Admin/Staff/tsa-1");
        await client.PostAsync("/Admin/Staff/tsa-1?handler=Activation", new FormUrlEncodedContent(new Dictionary<string, string> {["__RequestVerificationToken"] = token}));
        Assert.Equal(["c@example.com"], f.Identity.SetupEmails.ToArray());

        f.Api.Failures["adminIssueStaffActivation"] = "cannot_modify_owner";
        await client.PostAsync("/Admin/Staff/tsa-1?handler=Activation", new FormUrlEncodedContent(new Dictionary<string, string> {["__RequestVerificationToken"] = token}));
        Assert.Single(f.Identity.SetupEmails);
    }

    [Fact]
    public async Task Audit_filters_combine_and_reach_the_backend()
    {
        using var f = new AdminWebFactory();
        await f.Client(AdminWebFactory.Owner).GetStringAsync(
            "/Audit?actor=tsa-1&actorRole=trust_safety_admin&action=USER_BANNED&targetType=user&target=member-7&from=2026-09-01&to=2026-09-30");
        var sent = f.Api.Last("adminListAuditEvents");
        Assert.Equal("tsa-1", sent.GetProperty("actorAdminId").GetString());
        Assert.Equal("trust_safety_admin", sent.GetProperty("actorRole").GetString());
        Assert.Equal("USER_BANNED", sent.GetProperty("action").GetString());
        Assert.Equal("user", sent.GetProperty("targetType").GetString());
        Assert.Equal("member-7", sent.GetProperty("targetId").GetString());
        Assert.Equal("2026-09-01", sent.GetProperty("from").GetString());
        Assert.Equal("2026-09-30", sent.GetProperty("to").GetString());
    }

    [Fact]
    public async Task Audit_drops_values_outside_the_vocabulary()
    {
        using var f = new AdminWebFactory();
        await f.Client(AdminWebFactory.Owner).GetStringAsync("/Audit?action=DROP_TABLE&targetType=everything&from=yesterday");
        var sent = f.Api.Last("adminListAuditEvents");
        Assert.Equal(System.Text.Json.JsonValueKind.Null, sent.GetProperty("action").ValueKind);
        Assert.Equal(System.Text.Json.JsonValueKind.Null, sent.GetProperty("targetType").ValueKind);
        Assert.Equal(System.Text.Json.JsonValueKind.Null, sent.GetProperty("from").ValueKind);
    }

    [Fact]
    public async Task Partial_audit_scan_is_explained()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminListAuditEvents"] = _ => AdminWebFactory.Json("""{"items":[],"nextCursor":"abc","partial":true,"scanned":500}""");
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Audit?action=USER_BANNED");
        Assert.Contains("Searched 500 events", html);
    }

    [Fact]
    public async Task Owner_dashboard_shows_platform_counters_and_staff_actions()
    {
        using var f = new AdminWebFactory();
        f.Api.Responses["adminGetDashboard"] = _ => AdminWebFactory.Json("""
            {"counters":{"totalUsers":1200,"newUsers7d":45,"activeStaff":3,"disabledStaff":1,"bannedAccounts":2},
             "recentActions":[],
             "recentAdminActions":[{"eventId":"e1","action":"ADMIN_CREATED","actorAdminId":"owner-1","actorRole":"super_admin","targetType":"staff","targetId":"new-1","createdAt":"2026-09-30T09:00:00Z"}],
             "generatedAt":"2026-09-30T10:00:00Z"}
            """);
        var html = await f.Client(AdminWebFactory.Owner).GetStringAsync("/Dashboard");
        Assert.Contains("Platform &amp; staff", html);
        Assert.Contains("1200", html);
        Assert.Contains("Active staff", html);
        Assert.Contains("ADMIN_CREATED", html);
        Assert.DoesNotContain("Active members (7 days)", html);
    }
}
