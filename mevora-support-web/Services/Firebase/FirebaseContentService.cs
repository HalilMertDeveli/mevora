using Google.Cloud.Firestore;
using Mevora.Web.Data;
using Mevora.Web.Models;

namespace Mevora.Web.Services.Firebase;

public interface IFirebaseContentService
{
    Task<FaqLoadResult> GetPublishedFaqsAsync(CancellationToken cancellationToken = default);
}

public sealed record FaqLoadResult(IReadOnlyList<FaqItem> Items, bool FromFallback);

public sealed class FirebaseContentService : IFirebaseContentService
{
    private readonly IFirebaseService _firebase;
    private readonly ILogger<FirebaseContentService> _logger;

    public FirebaseContentService(IFirebaseService firebase, ILogger<FirebaseContentService> logger)
    {
        _firebase = firebase;
        _logger = logger;
    }

    public async Task<FaqLoadResult> GetPublishedFaqsAsync(CancellationToken cancellationToken = default)
    {
        if (!_firebase.IsAvailable || _firebase.Firestore is null)
        {
            return new FaqLoadResult(DefaultFaqData.Items, true);
        }

        try
        {
            var snapshot = await _firebase.Firestore
                .Collection("faqItems")
                .WhereEqualTo("isPublished", true)
                .OrderBy("order")
                .Limit(50)
                .GetSnapshotAsync(cancellationToken);

            if (snapshot.Count == 0)
            {
                _logger.LogInformation("faqItems empty — using local FAQ fallback.");
                return new FaqLoadResult(DefaultFaqData.Items, true);
            }

            var items = snapshot.Documents
                .Select(MapFaq)
                .Where(x => !string.IsNullOrWhiteSpace(x.Question))
                .OrderBy(x => x.Order)
                .ToList();

            if (items.Count == 0)
            {
                return new FaqLoadResult(DefaultFaqData.Items, true);
            }

            return new FaqLoadResult(items, false);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to load FAQ from Firestore. Using fallback.");
            return new FaqLoadResult(DefaultFaqData.Items, true);
        }
    }

    private static FaqItem MapFaq(DocumentSnapshot doc)
    {
        var data = doc.ToDictionary();
        return new FaqItem
        {
            Id = doc.Id,
            Question = GetString(data, "question"),
            Answer = GetString(data, "answer"),
            Category = GetString(data, "category", "general"),
            Order = GetInt(data, "order"),
            IsPublished = GetBool(data, "isPublished", true),
            CreatedAt = GetTimestamp(data, "createdAt"),
            UpdatedAt = GetTimestamp(data, "updatedAt"),
        };
    }

    private static string GetString(IReadOnlyDictionary<string, object> data, string key, string fallback = "")
        => data.TryGetValue(key, out var value) && value is not null ? value.ToString() ?? fallback : fallback;

    private static int GetInt(IReadOnlyDictionary<string, object> data, string key)
    {
        if (!data.TryGetValue(key, out var value) || value is null)
        {
            return 0;
        }

        return value switch
        {
            long l => (int)l,
            int i => i,
            double d => (int)d,
            _ => int.TryParse(value.ToString(), out var parsed) ? parsed : 0,
        };
    }

    private static bool GetBool(IReadOnlyDictionary<string, object> data, string key, bool fallback)
    {
        if (!data.TryGetValue(key, out var value) || value is null)
        {
            return fallback;
        }

        return value switch
        {
            bool b => b,
            _ => bool.TryParse(value.ToString(), out var parsed) ? parsed : fallback,
        };
    }

    private static DateTimeOffset GetTimestamp(IReadOnlyDictionary<string, object> data, string key)
    {
        if (data.TryGetValue(key, out var value) && value is Timestamp ts)
        {
            return ts.ToDateTimeOffset();
        }

        return DateTimeOffset.UtcNow;
    }
}
