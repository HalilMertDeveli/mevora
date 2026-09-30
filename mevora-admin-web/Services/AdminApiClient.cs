using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Mevora.Admin.Web.Configuration;
using Microsoft.Extensions.Options;

namespace Mevora.Admin.Web.Services;

/// <summary>A domain error returned by an admin command (never a raw backend exception).</summary>
public sealed class AdminApiException(string code, string? requestId = null, JsonElement? detail = null)
    : Exception(code)
{
    public string Code { get; } = code;
    public string? RequestId { get; } = requestId;
    public JsonElement? Detail { get; } = detail;

    /// <summary>The staff session is no longer valid (expired, revoked, disabled).</summary>
    public bool EndsSession => Code is "unauthenticated" or "session_revoked" or "staff_inactive" or "session_expired";

    public bool IsPermissionDenied => Code is "permission_denied" or "mfa_required";
}

public interface IAdminApiClient
{
    /// <summary>Runs one named admin command as the signed-in staff member.</summary>
    Task<JsonElement> CallAsync(string command, object? payload = null, CancellationToken ct = default);

    /// <summary>Runs a command with an explicit ID token (used during sign-in, before a session exists).</summary>
    Task<JsonElement> CallWithTokenAsync(string idToken, string command, object? payload = null, CancellationToken ct = default);
}

/// <summary>
/// Calls the admin callables (functions/src/admin) over the callable HTTP
/// protocol: POST {base}/{command} with {"data": …}. Every call carries the
/// staff member's ID token, the BFF credential and a correlation id; the
/// backend authorises each call on its own and this class trusts nothing it
/// does not get back from there.
/// </summary>
public sealed class AdminApiClient(
    HttpClient http,
    IOptions<AdminWebOptions> options,
    IStaffSession session,
    ILogger<AdminApiClient> logger) : IAdminApiClient
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly AdminWebOptions _options = options.Value;

    public async Task<JsonElement> CallAsync(string command, object? payload = null, CancellationToken ct = default)
    {
        var token = await session.GetIdTokenAsync(ct) ?? throw new AdminApiException("session_expired");
        return await CallWithTokenAsync(token, command, payload, ct);
    }

    public async Task<JsonElement> CallWithTokenAsync(string idToken, string command, object? payload = null, CancellationToken ct = default)
    {
        if (!System.Text.RegularExpressions.Regex.IsMatch(command, "^admin[A-Za-z]{3,60}$"))
        {
            throw new ArgumentException("Not an admin command.", nameof(command));
        }
        var requestId = Activity.Current?.TraceId.ToString() is { Length: > 0 } trace && trace != "00000000000000000000000000000000"
            ? trace
            : Guid.NewGuid().ToString("N");
        using var request = new HttpRequestMessage(HttpMethod.Post, $"{_options.FunctionsBaseUrl.TrimEnd('/')}/{command}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", idToken);
        request.Headers.TryAddWithoutValidation("x-mevora-admin-bff", _options.BffSharedSecret);
        request.Headers.TryAddWithoutValidation("x-request-id", requestId);
        request.Content = new StringContent(JsonSerializer.Serialize(new {data = payload ?? new { }}, Json), Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, ct);
        }
        catch (HttpRequestException error)
        {
            logger.LogError("admin_command_unreachable command={Command} requestId={RequestId} error={Error}", command, requestId, error.Message);
            throw new AdminApiException("backend_unavailable", requestId);
        }
        using (response)
        {
            var text = await response.Content.ReadAsStringAsync(ct);
            JsonElement body = default;
            try
            {
                if (!string.IsNullOrWhiteSpace(text)) body = JsonDocument.Parse(text).RootElement.Clone();
            }
            catch (JsonException)
            {
                // Fall through: a non-JSON body is an infrastructure failure.
            }

            if (response.IsSuccessStatusCode && body.ValueKind == JsonValueKind.Object && body.TryGetProperty("result", out var result))
            {
                return result.Clone();
            }

            var code = "internal_error";
            JsonElement? detail = null;
            if (body.ValueKind == JsonValueKind.Object && body.TryGetProperty("error", out var error))
            {
                if (error.TryGetProperty("details", out var details) && details.ValueKind == JsonValueKind.Object)
                {
                    detail = details.Clone();
                    if (details.TryGetProperty("code", out var c) && c.GetString() is { Length: > 0 } dc) code = dc;
                }
                else if (error.TryGetProperty("status", out var status))
                {
                    code = status.GetString() switch
                    {
                        "UNAUTHENTICATED" => "unauthenticated",
                        "PERMISSION_DENIED" => "permission_denied",
                        _ => "internal_error",
                    };
                }
            }
            else if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                code = "unauthenticated";
            }
            logger.LogWarning("admin_command_error command={Command} requestId={RequestId} code={Code} status={Status}",
                command, requestId, code, (int)response.StatusCode);
            throw new AdminApiException(code, requestId, detail);
        }
    }
}
