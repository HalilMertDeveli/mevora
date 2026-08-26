using System.Threading.RateLimiting;
using Mevora.Web.Configuration;
using Mevora.Web.Services;
using Mevora.Web.Services.Email;
using Mevora.Web.Services.Firebase;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<FirebaseSettings>(
    builder.Configuration.GetSection(FirebaseSettings.SectionName));
builder.Services.Configure<SiteSettings>(
    builder.Configuration.GetSection(SiteSettings.SectionName));
builder.Services.Configure<EmailSettings>(
    builder.Configuration.GetSection(EmailSettings.SectionName));

builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = FirebaseSupportService.MaxUploadBytes + (1024 * 1024);
});

builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<IFirebaseService, FirebaseService>();
builder.Services.AddScoped<IFirebaseSupportService, FirebaseSupportService>();
builder.Services.AddScoped<IFirebaseContentService, FirebaseContentService>();
builder.Services.AddScoped<ISiteUrlService, SiteUrlService>();
builder.Services.AddScoped<IEmailService, SmtpEmailService>();
builder.Services.AddSingleton<IEmailTemplateService, EmailTemplateService>();
builder.Services.AddScoped<ISupportNotificationService, SupportNotificationService>();

builder.Services.AddRazorPages();

builder.Services.AddAntiforgery(options =>
{
    options.HeaderName = "X-CSRF-TOKEN";
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("support", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 8,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
            }));
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}
else
{
    app.UseDeveloperExceptionPage();
}

app.Use(async (context, next) =>
{
    context.Response.Headers.TryAdd("X-Content-Type-Options", "nosniff");
    context.Response.Headers.TryAdd("X-Frame-Options", "DENY");
    context.Response.Headers.TryAdd("Referrer-Policy", "strict-origin-when-cross-origin");
    context.Response.Headers.TryAdd("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    await next();
});

if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseStaticFiles();
app.UseRouting();
app.UseRateLimiter();
app.UseStatusCodePagesWithReExecute("/Error", "?statusCode={0}");
app.UseAuthorization();

app.MapGet("/robots.txt", (ISiteUrlService urls) =>
{
    var sitemap = urls.Absolute("/sitemap.xml");
    var body = $"User-agent: *\nAllow: /\n\nSitemap: {sitemap}\n";
    return Results.Text(body, "text/plain; charset=utf-8");
});

app.MapGet("/sitemap.xml", (ISiteUrlService urls) =>
{
    string[] paths = ["/", "/support", "/faq", "/privacy", "/terms"];
    var urlsXml = string.Join(
        "\n",
        paths.Select(p =>
        {
            var loc = System.Security.SecurityElement.Escape(urls.Absolute(p));
            var priority = p == "/" ? "1.0" : "0.8";
            return $"  <url>\n    <loc>{loc}</loc>\n    <changefreq>weekly</changefreq>\n    <priority>{priority}</priority>\n  </url>";
        }));

    var xml = $"""
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        {urlsXml}
        </urlset>
        """;

    return Results.Content(xml, "application/xml; charset=utf-8");
});

app.MapRazorPages();

app.Run();

public partial class Program;
