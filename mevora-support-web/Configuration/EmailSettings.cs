namespace Mevora.Web.Configuration;

/// <summary>
/// SMTP / support mailbox settings. Passwords and API keys must come from
/// User Secrets or environment variables — never from source control.
/// </summary>
public sealed class EmailSettings
{
    public const string SectionName = "Email";

    /// <summary>When false, email sending is skipped (tickets still save to Firestore).</summary>
    public bool Enabled { get; set; }

    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;

    public string Username { get; set; } = string.Empty;

    /// <summary>Secret — set via Email__Password / User Secrets only.</summary>
    public string Password { get; set; } = string.Empty;

    public string SenderEmail { get; set; } = string.Empty;
    public string SenderName { get; set; } = "Mevora Support";

    /// <summary>Team inbox that receives new ticket notifications.</summary>
    public string SupportEmail { get; set; } = string.Empty;

    /// <summary>
    /// When true, sends a confirmation email to the submitter.
    /// Default false — enable only when you accept outbound mail to unverified addresses.
    /// </summary>
    public bool SendUserConfirmation { get; set; }

    public bool IsConfigured =>
        Enabled
        && !string.IsNullOrWhiteSpace(Host)
        && Port > 0
        && !string.IsNullOrWhiteSpace(SenderEmail)
        && !string.IsNullOrWhiteSpace(SupportEmail);
}
