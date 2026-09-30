using System.Text.Json;
using System.Text.RegularExpressions;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages.Audit;

/// <summary>
/// Read-only view of the append-only audit log: who did what, to whom, when.
/// Filters combine ("what did this moderator do to users this week?"); the
/// backend validates every value again. There is no edit or delete anywhere.
/// </summary>
[RequirePermission("audit.read")]
public sealed partial class IndexModel(IAdminApiClient api) : AdminPageModel(api)
{
    public string? Actor { get; private set; }
    public string? ActorRole { get; private set; }
    public string? Action { get; private set; }
    public string? TargetType { get; private set; }
    public string? Target { get; private set; }
    public string? CaseId { get; private set; }
    public string? From { get; private set; }
    public string? To { get; private set; }
    public string? Cursor { get; private set; }
    public JsonElement Result { get; private set; }

    public bool Filtered => Actor is not null || ActorRole is not null || Action is not null || TargetType is not null
        || Target is not null || CaseId is not null || From is not null || To is not null;

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}$")]
    private static partial Regex DayPattern();

    private static string? Day(string? value) => value is { Length: 10 } && DayPattern().IsMatch(value) ? value : null;

    private static string? OneOf(string? value, string[] allowed) => value is not null && allowed.Contains(value) ? value : null;

    public async Task OnGetAsync(string? actor, string? actorRole, string? action, string? targetType, string? target,
        string? caseId, string? from, string? to, string? cursor)
    {
        Actor = Clean(actor, 128);
        ActorRole = OneOf(Clean(actorRole, 40), Vocab.ActorRoles);
        Action = OneOf(Clean(action, 64), Vocab.AuditActions);
        TargetType = OneOf(Clean(targetType, 40), Vocab.AuditTargetTypes);
        Target = Clean(target, 300);
        CaseId = Clean(caseId, 128);
        From = Day(Clean(from, 10));
        To = Day(Clean(to, 10));
        Cursor = Clean(cursor, 1024);
        Result = await Load("adminListAuditEvents", new
        {
            actorAdminId = Actor,
            actorRole = ActorRole,
            action = Action,
            targetType = TargetType,
            targetId = Target,
            caseId = CaseId,
            from = From,
            to = To,
            cursor = Cursor,
            limit = 50,
        }) ?? default;
    }

    public PagerModel Pager => new("/Audit", Result.Str("nextCursor"),
        new Dictionary<string, string?>
        {
            ["actor"] = Actor,
            ["actorRole"] = ActorRole,
            ["action"] = Action,
            ["targetType"] = TargetType,
            ["target"] = Target,
            ["caseId"] = CaseId,
            ["from"] = From,
            ["to"] = To,
        },
        Cursor is not null);
}
