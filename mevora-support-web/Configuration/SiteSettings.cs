namespace Mevora.Web.Configuration;

/// <summary>
/// Public site identity and SEO URLs. No real production domain is hard-coded;
/// set BaseUrl when a domain is purchased.
/// </summary>
public sealed class SiteSettings
{
    public const string SectionName = "Site";

    public string SiteName { get; set; } = "Mevora";

    public string Tagline { get; set; } = "Daha Anlamlı Eşleşmeler";

    /// <summary>
    /// Absolute public origin without trailing slash, e.g. https://support.example.com
    /// Leave empty in development to derive from the current request.
    /// </summary>
    public string BaseUrl { get; set; } = string.Empty;

    /// <summary>Optional override; defaults to BaseUrl.</summary>
    public string CanonicalUrl { get; set; } = string.Empty;

    public string SupportEmail { get; set; } = "support@example.com";

    public string DefaultTitle => $"{SiteName} — {Tagline}";

    public string DefaultDescription { get; set; } =
        "Mevora, ortak ilgi alanları ve uyumluluk üzerinden daha anlamlı bağlantılar keşfetmeni sağlayan yeni nesil eşleşme uygulamasıdır.";

    public string ResolveBaseUrl(HttpRequest? request = null)
    {
        if (!string.IsNullOrWhiteSpace(BaseUrl))
        {
            return BaseUrl.TrimEnd('/');
        }

        if (request is not null)
        {
            return $"{request.Scheme}://{request.Host.Value}".TrimEnd('/');
        }

        return string.Empty;
    }

    public string ResolveCanonicalUrl(HttpRequest? request = null)
    {
        if (!string.IsNullOrWhiteSpace(CanonicalUrl))
        {
            return CanonicalUrl.TrimEnd('/');
        }

        return ResolveBaseUrl(request);
    }
}
