namespace Mevora.Admin.Web.Configuration;

/// <summary>
/// Everything the admin web needs to know about its environment.
///
/// None of it is a privileged credential: the Firebase web API key is public
/// by design, and the BFF shared secret only proves "this request came from
/// the admin web's server" — the staff member's own ID token, MFA and RBAC
/// are still checked by the backend on every command.
/// </summary>
public sealed class AdminWebOptions
{
    public const string Section = "AdminWeb";

    /// <summary>Firebase project id, e.g. mevora-d6ed0.</summary>
    public string ProjectId { get; set; } = "";

    /// <summary>Firebase Web API key (public).</summary>
    public string WebApiKey { get; set; } = "";

    /// <summary>host:port of the Auth emulator. Development only.</summary>
    public string? AuthEmulatorHost { get; set; }

    /// <summary>Base URL the admin callables live under.</summary>
    public string FunctionsBaseUrl { get; set; } = "";

    /// <summary>Shared secret presented as x-mevora-admin-bff. Never logged, never rendered.</summary>
    public string BffSharedSecret { get; set; } = "";

    /// <summary>Inactivity before the session ends.</summary>
    public int SessionIdleMinutes { get; set; } = 30;

    /// <summary>Hard cap on a session, however active.</summary>
    public int SessionAbsoluteHours { get; set; } = 8;

    /// <summary>Extra origins allowed in img-src (Firebase Storage, humor media CDNs).</summary>
    public string[] ImageOrigins { get; set; } = [];

    /// <summary>Human label shown in the header (e.g. "Emulator", "Production").</summary>
    public string EnvironmentLabel { get; set; } = "Production";

    public bool UsesAuthEmulator => !string.IsNullOrWhiteSpace(AuthEmulatorHost);

    /// <summary>The emulator-only BFF value the Functions emulator falls back to.</summary>
    public const string EmulatorDevBffSecret = "mevora-emulator-only-bff-secret";

    /// <summary>Fails startup on a configuration that would be unsafe in production.</summary>
    public IEnumerable<string> Validate(bool isDevelopment)
    {
        if (string.IsNullOrWhiteSpace(ProjectId)) yield return "AdminWeb:ProjectId is required.";
        if (string.IsNullOrWhiteSpace(WebApiKey)) yield return "AdminWeb:WebApiKey is required.";
        if (string.IsNullOrWhiteSpace(FunctionsBaseUrl)) yield return "AdminWeb:FunctionsBaseUrl is required.";
        if (string.IsNullOrWhiteSpace(BffSharedSecret) || BffSharedSecret.Length < 16)
            yield return "AdminWeb:BffSharedSecret must be set (at least 16 characters).";
        if (!isDevelopment)
        {
            if (UsesAuthEmulator) yield return "AdminWeb:AuthEmulatorHost must not be set outside Development.";
            if (BffSharedSecret == EmulatorDevBffSecret) yield return "The emulator BFF secret must not be used outside Development.";
            if (!FunctionsBaseUrl.StartsWith("https://", StringComparison.Ordinal))
                yield return "AdminWeb:FunctionsBaseUrl must be https outside Development.";
        }
        if (SessionIdleMinutes is < 5 or > 120) yield return "AdminWeb:SessionIdleMinutes must be 5-120.";
        if (SessionAbsoluteHours is < 1 or > 12) yield return "AdminWeb:SessionAbsoluteHours must be 1-12.";
    }
}
