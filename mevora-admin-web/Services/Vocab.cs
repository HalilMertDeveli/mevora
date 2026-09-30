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

    /// <summary>
    /// Roles the console can hand out. super_admin is not one of them: the
    /// owner is the platform's super admin and no console action creates another.
    /// </summary>
    public static readonly string[] GrantableRoles = ["trust_safety_admin", "senior_moderator", "moderator", "support_agent"];

    /// <summary>Who can appear as an audit actor: every role plus scheduled jobs.</summary>
    public static readonly string[] ActorRoles = [.. Roles, "system"];

    public static readonly string[] AuditTargetTypes =
    [
        "user", "case", "report", "photo", "humor_content", "support_ticket", "verification",
        "automation_job", "review_item", "appeal", "staff", "app_config", "system",
    ];

    public static readonly string[] AuditActions =
    [
        "ADMIN_LOGIN", "SENSITIVE_PROFILE_VIEWED",
        "CASE_CREATED", "CASE_ASSIGNED", "CASE_UNASSIGNED", "CASE_STATUS_CHANGED", "CASE_RESOLVED", "CASE_ESCALATED", "CASE_NOTE_ADDED",
        "REPORT_RESOLVED",
        "USER_WARNED", "USER_SUSPENDED", "USER_BANNED", "USER_RESTORED", "USER_SUSPENSION_EXPIRED", "AUTH_SYNC_FAILED",
        "PHOTO_APPROVED", "PHOTO_REJECTED", "PHOTO_REMOVED", "PHOTO_ESCALATED",
        "HUMOR_APPROVED", "HUMOR_REJECTED", "HUMOR_ESCALATED",
        "VERIFICATION_REVERIFICATION_REQUIRED", "VERIFICATION_ESCALATED",
        "SUPPORT_ASSIGNED", "SUPPORT_REPLIED", "SUPPORT_STATUS_CHANGED", "SUPPORT_RESOLVED", "SUPPORT_ESCALATED", "SUPPORT_NOTE_ADDED",
        "AUTOMATION_JOB_RETRIED", "AUTOMATION_JOB_RESOLVED", "AUTOMATION_JOB_DISMISSED", "AUTOMATION_JOB_ESCALATED", "REVIEW_ITEM_RESOLVED",
        "APPEAL_SUBMITTED", "APPEAL_OPENED_BY_STAFF", "APPEAL_ASSIGNED", "APPEAL_ACCEPTED", "APPEAL_REJECTED",
        "ADMIN_CREATED", "ADMIN_GRANTED", "ADMIN_ROLE_CHANGED", "ADMIN_DISABLED", "ADMIN_ENABLED", "ADMIN_SESSIONS_REVOKED", "ADMIN_ACTIVATION_ISSUED",
        "MAINTENANCE_RUN",
        "APP_MAINTENANCE_ENABLED", "APP_MAINTENANCE_DISABLED", "APP_MIN_VERSION_CHANGED", "APP_FEATURE_SWITCH_CHANGED", "APP_ANNOUNCEMENT_CHANGED",
    ];

    /// <summary>Suspension presets in hours. "custom" lets the moderator enter hours (1–8760).</summary>
    public static readonly (string Value, string Label)[] SuspensionPresets =
        [("24", "24 hours"), ("72", "3 days"), ("168", "7 days"), ("720", "30 days"), ("custom", "Custom…")];

    public const int MinSuspensionHours = 1;
    public const int MaxSuspensionHours = 24 * 365;
}
