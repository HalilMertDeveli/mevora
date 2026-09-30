using System.Text.Json;
using Mevora.Admin.Web.Security;
using Mevora.Admin.Web.Services;

namespace Mevora.Admin.Web.Pages;

[RequirePermission("dashboard.read")]
public sealed class DashboardModel(IAdminApiClient api) : AdminPageModel(api)
{
    public JsonElement Data { get; private set; }

    public async Task OnGetAsync()
    {
        Data = await Load("adminGetDashboard") ?? default;
    }

    public string Count(string key)
    {
        var n = Data.Get("counters").Num(key);
        return n?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "—";
    }

    public bool Shows(string key) => Data.Get("counters").Has(key);
}
