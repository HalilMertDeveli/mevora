namespace Mevora.Web.Models;

public static class SupportTicketStatuses
{
    public const string Open = "Open";
    public const string InProgress = "InProgress";
    public const string Resolved = "Resolved";
    public const string Closed = "Closed";
}

public static class SupportPriorities
{
    public const string Low = "Low";
    public const string Normal = "Normal";
    public const string High = "High";
    public const string Urgent = "Urgent";
}

public static class SupportCategories
{
    public const string AccountLogin = "account_login";
    public const string Profile = "profile";
    public const string Matching = "matching";
    public const string Messaging = "messaging";
    public const string Media = "media";
    public const string Notifications = "notifications";
    public const string PaymentBoost = "payment_boost";
    public const string PrivacySecurity = "privacy_security";
    public const string Technical = "technical";

    public static IReadOnlyList<(string Value, string Label)> All { get; } =
    [
        (AccountLogin, "Hesap ve giriş"),
        (Profile, "Profil"),
        (Matching, "Eşleşmeler"),
        (Messaging, "Mesajlaşma"),
        (Media, "Fotoğraf ve medya"),
        (Notifications, "Bildirimler"),
        (PaymentBoost, "Boost / ödeme"),
        (PrivacySecurity, "Gizlilik ve güvenlik"),
        (Technical, "Teknik problemler"),
    ];
}
