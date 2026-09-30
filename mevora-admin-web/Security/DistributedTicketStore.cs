using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Caching.Distributed;

namespace Mevora.Admin.Web.Security;

/// <summary>
/// Keeps authentication tickets (and the Firebase tokens inside them) on the
/// server. The browser's cookie carries only an opaque, data-protected key, so
/// signing out removes the session for real and a copied cookie is worthless
/// once the ticket is gone.
///
/// Backed by IDistributedCache: in-memory for a single instance; register a
/// shared cache (e.g. Redis) before running more than one instance.
/// </summary>
public sealed class DistributedTicketStore(IDistributedCache cache) : ITicketStore
{
    private const string Prefix = "mevora-admin-session:";

    public async Task<string> StoreAsync(AuthenticationTicket ticket)
    {
        var key = Guid.NewGuid().ToString("N");
        await RenewAsync(key, ticket);
        return key;
    }

    public Task RenewAsync(string key, AuthenticationTicket ticket)
    {
        var options = new DistributedCacheEntryOptions();
        if (ticket.Properties.ExpiresUtc is { } expires)
        {
            options.AbsoluteExpiration = expires;
        }
        else
        {
            options.SlidingExpiration = TimeSpan.FromMinutes(30);
        }
        return cache.SetAsync(Prefix + key, TicketSerializer.Default.Serialize(ticket), options);
    }

    public async Task<AuthenticationTicket?> RetrieveAsync(string key)
    {
        var bytes = await cache.GetAsync(Prefix + key);
        return bytes is null ? null : TicketSerializer.Default.Deserialize(bytes);
    }

    public Task RemoveAsync(string key) => cache.RemoveAsync(Prefix + key);
}
