using Google.Cloud.Firestore;
using Google.Cloud.Storage.V1;
using Mevora.Web.Configuration;
using Mevora.Web.Models;
using Mevora.Web.Services.Email;
using Mevora.Web.Services.Firebase;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace Mevora.Support.Web.Tests;

/// <summary>
/// A website ticket must never claim a member identity: the app lists a member's
/// tickets by <c>userId == uid</c>, so a visitor-typed uid in <c>userId</c> would
/// plant the ticket in that member's in-app list.
/// </summary>
public class WebsiteSupportTicketTests
{
    private const string TicketId = "Tk9aBcDeFgHiJkLmNoPq";
    private const string MemberUid = "a1B2c3D4e5F6g7H8i9J0k1L2m3N4";
    private static readonly Timestamp Now = Timestamp.FromDateTimeOffset(new DateTimeOffset(2026, 9, 30, 12, 0, 0, TimeSpan.Zero));

    private static SupportTicketDraft Draft(string? userId) => new(
        Name: "  Ayşe Visitor  ",
        Email: "  Visitor@Example.COM ",
        UserId: userId,
        Category: "account_login",
        Subject: "  Cannot log in  ",
        Description: "  I cannot log in to my account.  ",
        Priority: SupportPriorities.Normal);

    [Fact]
    public void Typed_member_uid_is_kept_as_a_claim_and_never_becomes_the_userId()
    {
        var data = WebsiteSupportTicket.BuildDocument(TicketId, Draft(MemberUid), Now, attachmentUrl: null);

        Assert.Equal($"web-{TicketId}", data["userId"]);
        Assert.NotEqual(MemberUid, data["userId"]);
        Assert.Equal(MemberUid, data["claimedUserId"]);
        Assert.Equal("website", data["source"]);
        Assert.Equal(
            ["claimedUserId"],
            data.Where(kv => kv.Value is string s && s == MemberUid).Select(kv => kv.Key));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("<>!#$%")]
    public void Blank_or_unusable_claim_is_omitted(string? typed)
    {
        var data = WebsiteSupportTicket.BuildDocument(TicketId, Draft(typed), Now, attachmentUrl: null);

        Assert.Equal($"web-{TicketId}", data["userId"]);
        Assert.False(data.ContainsKey("claimedUserId"));
    }

    [Fact]
    public void A_claim_that_mimics_another_web_ticket_still_does_not_change_userId()
    {
        var data = WebsiteSupportTicket.BuildDocument(TicketId, Draft("web-SomeOtherTicket"), Now, attachmentUrl: null);

        Assert.Equal($"web-{TicketId}", data["userId"]);
        Assert.Equal("web-SomeOtherTicket", data["claimedUserId"]);
    }

    [Fact]
    public void Claim_is_trimmed_stripped_and_capped()
    {
        Assert.Equal("abcscript", WebsiteSupportTicket.NormalizeClaimedUserId("  abc<script>  "));
        Assert.Equal("user.name-1@x_y", WebsiteSupportTicket.NormalizeClaimedUserId("user.name-1@x_y"));

        var capped = WebsiteSupportTicket.NormalizeClaimedUserId(new string('a', 300));
        Assert.Equal(WebsiteSupportTicket.MaxClaimedUserIdLength, capped!.Length);
    }

    [Fact]
    public void Document_keeps_the_existing_website_ticket_shape()
    {
        const string attachment = $"support/{TicketId}/shot.png";
        var data = WebsiteSupportTicket.BuildDocument(TicketId, Draft(null), Now, attachment);

        Assert.Equal(TicketId, data["id"]);
        Assert.Equal("Ayşe Visitor", data["name"]);
        Assert.Equal("visitor@example.com", data["email"]);
        Assert.Equal("Cannot log in", data["subject"]);
        Assert.Equal("I cannot log in to my account.", data["description"]);
        Assert.Equal(data["description"], data["message"]);
        Assert.Equal(SupportPriorities.Normal, data["priority"]);
        Assert.Equal(SupportTicketStatuses.Open, data["status"]);
        Assert.Equal(new List<string> { attachment }, data["attachments"]);
        Assert.Equal(attachment, data["attachmentUrl"]);
        Assert.Equal(Now, data["createdAt"]);
        Assert.Equal(Now, data["updatedAt"]);
    }

    [Fact]
    public void No_attachment_means_empty_list_and_no_attachmentUrl()
    {
        var data = WebsiteSupportTicket.BuildDocument(TicketId, Draft(null), Now, attachmentUrl: null);

        Assert.Empty((List<string>)data["attachments"]);
        Assert.False(data.ContainsKey("attachmentUrl"));
    }

    [Fact]
    public async Task Unavailable_firebase_rejects_without_writing_or_notifying()
    {
        var notifications = new RecordingNotifications();
        var service = new FirebaseSupportService(
            new UnavailableFirebase(),
            notifications,
            NullLogger<FirebaseSupportService>.Instance);

        var result = await service.CreateTicketAsync(Draft(MemberUid), screenshot: null);

        Assert.False(result.Succeeded);
        Assert.False(result.UsedFirebase);
        Assert.Null(result.TicketId);
        Assert.Equal(0, notifications.Calls);
    }

    [Fact]
    public async Task Team_email_labels_the_typed_id_as_an_unverified_claim()
    {
        var email = new RecordingEmail();
        var service = new SupportNotificationService(
            email,
            new EmailTemplateService(new TestEnvironment()),
            Options.Create(new EmailSettings { SupportEmail = "team@example.com" }),
            Options.Create(new SiteSettings()),
            NullLogger<SupportNotificationService>.Instance);

        await service.NotifyTicketCreatedAsync(Draft(MemberUid), TicketId, "<b>" + MemberUid);

        var message = Assert.Single(email.Sent);
        Assert.Contains($"Claimed user ID (unverified): <b>{MemberUid}", message.PlainTextBody);
        Assert.Contains("Claimed user ID (unverified)", message.HtmlBody);
        Assert.Contains($"&lt;b&gt;{MemberUid}", message.HtmlBody);
        Assert.DoesNotContain("{{", message.HtmlBody);
    }

    [Fact]
    public async Task Team_email_shows_none_when_nothing_was_claimed()
    {
        var email = new RecordingEmail();
        var service = new SupportNotificationService(
            email,
            new EmailTemplateService(new TestEnvironment()),
            Options.Create(new EmailSettings { SupportEmail = "team@example.com" }),
            Options.Create(new SiteSettings()),
            NullLogger<SupportNotificationService>.Instance);

        await service.NotifyTicketCreatedAsync(Draft(null), TicketId, claimedUserId: null);

        Assert.Contains("Claimed user ID (unverified): (none)", Assert.Single(email.Sent).PlainTextBody);
    }

    private sealed class UnavailableFirebase : IFirebaseService
    {
        public bool IsAvailable => false;
        public string? UnavailableReason => "test";
        public FirestoreDb? Firestore => null;
        public StorageClient? Storage => null;
        public string? StorageBucket => null;
    }

    private sealed class RecordingNotifications : ISupportNotificationService
    {
        public int Calls { get; private set; }

        public Task NotifyTicketCreatedAsync(
            SupportTicketDraft draft,
            string ticketId,
            string? claimedUserId,
            CancellationToken cancellationToken = default)
        {
            Calls++;
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingEmail : IEmailService
    {
        public List<EmailMessage> Sent { get; } = [];
        public bool IsAvailable => true;

        public Task<EmailSendResult> SendAsync(EmailMessage message, CancellationToken cancellationToken = default)
        {
            Sent.Add(message);
            return Task.FromResult(new EmailSendResult(true, null, false));
        }
    }

    /// <summary>Content root is the test output, where the web project's EmailTemplates are copied.</summary>
    private sealed class TestEnvironment : IWebHostEnvironment
    {
        public string WebRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string ApplicationName { get; set; } = "Mevora.Support.Web.Tests";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public string EnvironmentName { get; set; } = "Testing";
    }
}
