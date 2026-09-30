using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;

namespace Mevora.Admin.Web.Security;

public static class StaffClaims
{
    public const string Uid = "mevora:uid";
    public const string Role = "mevora:role";
    public const string Permission = "mevora:perm";
    public const string Mfa = "mevora:mfa";
    public const string SessionStarted = "mevora:session_started";
    public const string Owner = "mevora:owner";

    public const string PolicyPrefix = "perm:";

    public static bool Can(this ClaimsPrincipal user, string permission) =>
        user.HasClaim(Permission, permission);

    public static string? StaffUid(this ClaimsPrincipal user) => user.FindFirst(Uid)?.Value;

    public static string? StaffRole(this ClaimsPrincipal user) => user.FindFirst(Role)?.Value;

    public static bool UsedMfa(this ClaimsPrincipal user) => user.FindFirst(Mfa)?.Value == "true";

    /// <summary>Display only (an "Owner" label); every owner protection is enforced by the backend.</summary>
    public static bool IsOwner(this ClaimsPrincipal user) => user.FindFirst(Owner)?.Value == "true";
}

/// <summary>
/// [Authorize(Policy = "perm:case.read")] resolves to "holds that permission".
///
/// This only decides what the console shows. The backend re-checks the same
/// permission on every command against the adminStaff record, so a page that
/// renders is never, by itself, authority to act.
/// </summary>
public sealed class PermissionPolicyProvider(Microsoft.Extensions.Options.IOptions<AuthorizationOptions> options)
    : DefaultAuthorizationPolicyProvider(options)
{
    public override async Task<AuthorizationPolicy?> GetPolicyAsync(string policyName)
    {
        if (policyName.StartsWith(StaffClaims.PolicyPrefix, StringComparison.Ordinal))
        {
            return new AuthorizationPolicyBuilder()
                .RequireAuthenticatedUser()
                .RequireClaim(StaffClaims.Permission, policyName[StaffClaims.PolicyPrefix.Length..])
                .Build();
        }
        return await base.GetPolicyAsync(policyName);
    }
}

/// <summary>Shorthand: [RequirePermission("case.read")].</summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class RequirePermissionAttribute(string permission) : AuthorizeAttribute(StaffClaims.PolicyPrefix + permission);
