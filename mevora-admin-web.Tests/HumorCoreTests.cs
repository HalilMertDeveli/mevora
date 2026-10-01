using System.Net;

namespace Mevora.Admin.Web.Tests;

/// <summary>
/// Humor Core sequence page: every position with what it measures and whether
/// members can be given it — and nothing on the page that could change it.
/// </summary>
public sealed class HumorCoreTests
{
    private const string HumorReader = "mod-1|moderator|dashboard.read,humor.read,humor.moderate";

    private static readonly string Sequence = """
        {"released":false,"onboardingCount":15,"dailyCount":5,"total":3,"servableCount":2,"healthy":false,
         "problems":[],"warnings":["V2 hc_gif_two: content rejected"],
         "items":[
          {"position":1,"contentId":"hc_gif_one","onboarding":true,"coreStatus":"active","retiredReason":null,"supersedes":null,
           "servable":true,"contentExists":true,"contentActive":true,"safetyStatus":"approved","type":"meme","category":"sarcasm",
           "vectorSummary":["sarcasm 0.88","teasing 0.35"],"provider":"giphy","sourceTrust":"curated",
           "previewUrl":"https://media.giphy.com/media/one/giphy_s.gif","ratingCount":12},
          {"position":2,"contentId":"hc_gif_two","onboarding":true,"coreStatus":"active","retiredReason":null,"supersedes":null,
           "servable":false,"contentExists":true,"contentActive":true,"safetyStatus":"rejected","type":"meme","category":"absurd",
           "vectorSummary":["absurd 0.86"],"provider":"giphy","sourceTrust":"curated","previewUrl":null,"ratingCount":0},
          {"position":16,"contentId":"hc_gif_old","onboarding":false,"coreStatus":"retired","retiredReason":"clip removed by provider","supersedes":null,
           "servable":false,"contentExists":true,"contentActive":false,"safetyStatus":"approved","type":"meme","category":"dry",
           "vectorSummary":["dry 0.9"],"provider":"giphy","sourceTrust":"curated","previewUrl":null,"ratingCount":40}
         ]}
        """;

    private static AdminWebFactory Factory()
    {
        var f = new AdminWebFactory();
        f.Api.Responses["adminListHumorCoreSequence"] = _ => AdminWebFactory.Json(Sequence);
        f.Api.Responses["adminListHumorReviews"] = _ => AdminWebFactory.Json("""{"items":[],"nextCursor":null}""");
        return f;
    }

    [Fact]
    public async Task Lists_every_position_with_status_measurement_and_source()
    {
        using var f = Factory();
        var html = await f.Client(HumorReader).GetStringAsync("/Humor/Core");

        Assert.True(f.Api.Called("adminListHumorCoreSequence"));
        foreach (var expected in new[]
                 {
                     "V1", "V2", "V16", "hc_gif_one", "hc_gif_two", "hc_gif_old",
                     "sarcasm 0.88", "giphy", "clip removed by provider",
                     "V2 hc_gif_two: content rejected",
                     "https://media.giphy.com/media/one/giphy_s.gif",
                 })
        {
            Assert.Contains(expected, html);
        }
        // Draft and unhealthy are said out loud, not left to be inferred.
        Assert.Contains("badge-warn", html);
        Assert.Contains("badge-danger", html);
    }

    [Fact]
    public async Task The_page_offers_no_way_to_change_the_sequence()
    {
        using var f = Factory();
        var client = f.Client(HumorReader);
        var html = await client.GetStringAsync("/Humor/Core");

        // The page body — everything after its heading — holds no form, button
        // or handler. (The surrounding layout has its own sign-out form.)
        var start = html.IndexOf("class=\"page-head\"", StringComparison.Ordinal);
        Assert.True(start >= 0);
        var end = html.IndexOf("</main>", start, StringComparison.Ordinal);
        var body = end > start ? html[start..end] : html[start..];
        Assert.Contains("hc_gif_one", body);
        Assert.DoesNotContain("<form", body);
        Assert.DoesNotContain("<button", body);
        Assert.DoesNotContain("<input", body);
        Assert.DoesNotContain("handler=", body);
        var post = await client.PostAsync("/Humor/Core", new FormUrlEncodedContent(new Dictionary<string, string>()));
        Assert.NotEqual(HttpStatusCode.OK, post.StatusCode);
        Assert.Single(f.Api.Calls);
    }

    [Fact]
    public async Task Staff_without_humor_read_get_403()
    {
        using var f = Factory();
        var response = await f.Client(AdminWebFactory.SupportAgent).GetAsync("/Humor/Core");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Empty(f.Api.Calls);
    }

    [Fact]
    public async Task The_moderation_queue_links_to_the_sequence()
    {
        using var f = Factory();
        var html = await f.Client(HumorReader).GetStringAsync("/Humor");
        Assert.Contains("href=\"/Humor/Core\"", html);
    }
}
