using Mevora.Web.Configuration;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;

namespace Mevora.Web.Services;

public interface ISiteUrlService
{
    string BaseUrl { get; }
    string Absolute(string path);
    string CanonicalFor(PathString path);
}

public sealed class SiteUrlService : ISiteUrlService
{
    private readonly SiteSettings _settings;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public SiteUrlService(IOptions<SiteSettings> options, IHttpContextAccessor httpContextAccessor)
    {
        _settings = options.Value;
        _httpContextAccessor = httpContextAccessor;
    }

    public string BaseUrl =>
        _settings.ResolveCanonicalUrl(_httpContextAccessor.HttpContext?.Request);

    public string Absolute(string path)
    {
        var baseUrl = BaseUrl;
        if (string.IsNullOrEmpty(baseUrl))
        {
            return path;
        }

        if (string.IsNullOrWhiteSpace(path) || path == "/")
        {
            return baseUrl + "/";
        }

        return path.StartsWith('/') ? baseUrl + path : $"{baseUrl}/{path}";
    }

    public string CanonicalFor(PathString path) => Absolute(path.HasValue ? path.Value! : "/");
}
