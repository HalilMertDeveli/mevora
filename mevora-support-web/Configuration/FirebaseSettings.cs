namespace Mevora.Web.Configuration;

/// <summary>
/// Firebase configuration. Secrets must come from User Secrets, environment
/// variables, or Application Default Credentials — never from source control.
/// </summary>
public sealed class FirebaseSettings
{
    public const string SectionName = "Firebase";

    /// <summary>Firebase project id, e.g. mevora-d6ed0.</summary>
    public string ProjectId { get; set; } = string.Empty;

    /// <summary>Storage bucket, e.g. mevora-d6ed0.appspot.com.</summary>
    public string StorageBucket { get; set; } = string.Empty;

    /// <summary>
    /// Absolute path to a service account JSON file.
    /// Prefer env GOOGLE_APPLICATION_CREDENTIALS or Firebase:ServiceAccountPath.
    /// </summary>
    public string? ServiceAccountPath { get; set; }

    /// <summary>
    /// Raw service account JSON (production secret store / env Firebase__ServiceAccountJson).
    /// Do not put real values in appsettings.json.
    /// </summary>
    public string? ServiceAccountJson { get; set; }

    /// <summary>When false, Firebase clients are not created and fallbacks are used.</summary>
    public bool Enabled { get; set; } = true;

    public bool IsConfigured =>
        Enabled
        && !string.IsNullOrWhiteSpace(ProjectId)
        && (
            !string.IsNullOrWhiteSpace(ServiceAccountPath)
            || !string.IsNullOrWhiteSpace(ServiceAccountJson)
            || !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS"))
        );
}
