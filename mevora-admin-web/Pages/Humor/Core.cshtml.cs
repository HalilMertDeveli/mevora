using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages.Humor;

/// <summary>
/// The Humor Core sequence, read-only: every position, what it measures and
/// whether a member can be given it. The page has no handler that changes
/// anything — the order is code, frozen by a lock fixture.
/// </summary>
[RequirePermission("humor.read")]
public sealed class CoreModel(IAdminApiClient api) : AdminPageModel(api)
{
    public JsonElement Result { get; private set; }

    public async Task OnGetAsync()
    {
        Result = await Load("adminListHumorCoreSequence") ?? default;
    }
}
