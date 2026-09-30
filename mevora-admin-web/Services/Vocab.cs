namespace Mevora.Admin.Web.Services;

/// <summary>
/// The code lists the forms offer. They mirror functions/src/admin; the
/// backend validates every value again, so a stale list here can only make a
/// form fail, never let an unknown code through.
/// </summary>
public static class Vocab
{
    public static readonly string[] ReasonCodes =
    [
        "HARASSMENT", "HATE_SPEECH", "SCAM_FRAUD", "SPAM", "FAKE_PROFILE", "IMPERSONATION", "UNDERAGE",
        "INAPPROPRIATE_CONTENT", "NUDITY_SEXUAL_CONTENT", "VIOLENCE_THREATS", "SELF_HARM_RISK", "BAN_EVASION",
        "PAYMENT_ABUSE", "TERMS_VIOLATION", "OTHER",
    ];

    public static readonly string[] RestoreReasonCodes =
        ["APPEAL_ACCEPTED", "ERROR_CORRECTION", "SUSPENSION_REVIEWED", "NEW_EVIDENCE", "OTHER"];

    public static readonly string[] PhotoRejectReasons =
    [
        "NUDITY_SEXUAL_CONTENT", "VIOLENCE_GORE", "HATE_SYMBOLS", "NOT_A_PERSON", "IMPERSONATION",
        "MINOR_IN_PHOTO", "LOW_QUALITY", "CONTACT_INFO", "OTHER",
    ];

    public static readonly string[] ResolutionCodes =
        ["action_taken", "no_violation", "insufficient_evidence", "duplicate", "subject_deleted", "resolved_elsewhere", "other"];

    public static readonly string[] CaseTypes =
        ["USER_REPORT", "PHOTO_REVIEW", "HUMOR_REVIEW", "VERIFICATION_REVIEW", "SUPPORT_ESCALATION", "AUTOMATION_REVIEW", "APPEAL"];

    public static readonly string[] Roles = ["support_agent", "moderator", "senior_moderator", "trust_safety_admin", "super_admin"];

    /// <summary>Suspension presets in hours. "custom" lets the moderator enter hours (1–8760).</summary>
    public static readonly (string Value, string Label)[] SuspensionPresets =
        [("24", "24 hours"), ("72", "3 days"), ("168", "7 days"), ("720", "30 days"), ("custom", "Custom…")];

    public const int MinSuspensionHours = 1;
    public const int MaxSuspensionHours = 24 * 365;
}
