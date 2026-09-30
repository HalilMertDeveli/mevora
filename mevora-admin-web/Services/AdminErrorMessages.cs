namespace Mevora.Admin.Web.Services;

/// <summary>Domain error code → message a staff member can act on. Never shows raw backend errors.</summary>
public static class AdminErrorMessages
{
    private static readonly Dictionary<string, string> Messages = new(StringComparer.Ordinal)
    {
        ["permission_denied"] = "Your role does not allow this action.",
        ["mfa_required"] = "This action needs a session signed in with two-factor authentication.",
        ["unauthenticated"] = "Your session has ended. Please sign in again.",
        ["session_revoked"] = "Your session was revoked (for example after a role change). Please sign in again.",
        ["session_expired"] = "Your session has ended. Please sign in again.",
        ["staff_inactive"] = "Your staff access is not active.",
        ["invalid_argument"] = "Some of the information entered is missing or invalid.",
        ["not_found"] = "That record no longer exists.",
        ["rate_limited"] = "Too many requests in a short time. Wait a minute and try again.",
        ["case_already_assigned"] = "Someone else has already taken this. Refresh to see who.",
        ["case_not_assigned_to_you"] = "This is assigned to someone else.",
        ["invalid_state_transition"] = "That change is not possible from the record's current state. Refresh and check.",
        ["user_already_banned"] = "This account is already banned.",
        ["user_already_suspended"] = "This account is already suspended. Restore it first to change the suspension.",
        ["user_not_restricted"] = "This account is not suspended or banned.",
        ["user_deleted"] = "This account has been deleted.",
        ["cannot_modify_self"] = "You cannot take this action on your own account.",
        ["cannot_modify_super_admin"] = "A super admin cannot be actioned. Another super admin must change their role first.",
        ["cannot_modify_staff"] = "This staff member's role is at or above yours.",
        ["last_super_admin"] = "This is the last active super admin and cannot be removed.",
        ["role_grant_forbidden"] = "You cannot grant a role at or above your own.",
        ["photo_already_reviewed"] = "This photo already has a final decision.",
        ["photo_review_in_progress"] = "Another reviewer is deciding this photo right now.",
        ["appeal_already_resolved"] = "This appeal has already been decided.",
        ["appeal_not_allowed"] = "This decision cannot be appealed.",
        ["appeal_window_closed"] = "The appeal window for this decision has closed.",
        ["appeal_self_review"] = "You made the original decision, so another moderator must review the appeal.",
        ["unsupported_job_action"] = "That action is not available for this job type.",
        ["ticket_closed"] = "This ticket is closed.",
        ["verification_override_forbidden"] = "Verification can only be granted by the identity provider.",
        ["conflict"] = "Someone changed this at the same time. Refresh and try again.",
        ["backend_unavailable"] = "The admin service is unreachable. Try again shortly.",
        ["internal_error"] = "Something went wrong on the server. The error was logged.",
    };

    public static string For(string code) =>
        Messages.TryGetValue(code, out var message) ? message : Messages["internal_error"];

    public static string For(AdminApiException error) =>
        error.RequestId is { Length: > 0 } id ? $"{For(error.Code)} (ref {id[..Math.Min(12, id.Length)]})" : For(error.Code);
}
