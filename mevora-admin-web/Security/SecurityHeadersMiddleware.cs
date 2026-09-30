using Mevora.Admin.Web.Configuration;
using Microsoft.Extensions.Options;

namespace Mevora.Admin.Web.Security;

/// <summary>
/// Security headers for every response. Stricter than the public support site:
/// no inline script or style at all, no framing, no referrer, no caching of
/// authenticated pages, and the browser may only talk back to this origin.
/// </summary>
public sealed class SecurityHeadersMiddleware(RequestDelegate next, IOptions<AdminWebOptions> options)
{
    private readonly string _csp = BuildCsp(options.Value);

    internal static string BuildCsp(AdminWebOptions options)
    {
        var images = string.Join(' ', new[] {"'self'"}.Concat(options.ImageOrigins.Where(o =>
            Uri.TryCreate(o, UriKind.Absolute, out var u) && (u.Scheme == "https" || u.IsLoopback))));
        return string.Join("; ",
            "default-src 'none'",
            "script-src 'self'",
            "style-src 'self'",
            $"img-src {images}",
            "font-src 'self'",
            "connect-src 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
            "base-uri 'none'",
            "object-src 'none'",
            "manifest-src 'self'");
    }

    public Task InvokeAsync(HttpContext context)
    {
        context.Response.OnStarting(() =>
        {
            var headers = context.Response.Headers;
            headers["Content-Security-Policy"] = _csp;
            headers["X-Content-Type-Options"] = "nosniff";
            headers["X-Frame-Options"] = "DENY";
            headers["Referrer-Policy"] = "no-referrer";
            headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), payment=(), usb=()";
            headers["Cross-Origin-Opener-Policy"] = "same-origin";
            headers["Cross-Origin-Resource-Policy"] = "same-origin";
            headers["X-Robots-Tag"] = "noindex, nofollow";
            // Nothing the console renders may be cached by the browser or a proxy.
            if (!context.Request.Path.StartsWithSegments("/css") && !context.Request.Path.StartsWithSegments("/js"))
            {
                headers["Cache-Control"] = "no-store";
                headers["Pragma"] = "no-cache";
            }
            headers.Remove("Server");
            headers.Remove("X-Powered-By");
            return Task.CompletedTask;
        });
        return next(context);
    }
}
