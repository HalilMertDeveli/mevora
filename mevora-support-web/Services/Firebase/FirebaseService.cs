using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Google.Cloud.Firestore;
using Google.Cloud.Storage.V1;
using Mevora.Web.Configuration;
using Microsoft.Extensions.Options;

namespace Mevora.Web.Services.Firebase;

public interface IFirebaseService
{
    bool IsAvailable { get; }
    string? UnavailableReason { get; }
    FirestoreDb? Firestore { get; }
    StorageClient? Storage { get; }
    string? StorageBucket { get; }
}

/// <summary>
/// Resolves Firebase credentials without hard-coding secrets.
/// Order: ADC / GOOGLE_APPLICATION_CREDENTIALS → ServiceAccountJson → ServiceAccountPath.
/// </summary>
public sealed class FirebaseService : IFirebaseService, IDisposable
{
    private readonly ILogger<FirebaseService> _logger;
    private readonly FirebaseSettings _settings;
    private readonly object _gate = new();
    private bool _initialized;
    private FirestoreDb? _firestore;
    private StorageClient? _storage;

    public FirebaseService(IOptions<FirebaseSettings> options, ILogger<FirebaseService> logger)
    {
        _settings = options.Value;
        _logger = logger;
        TryInitialize();
    }

    public bool IsAvailable { get; private set; }
    public string? UnavailableReason { get; private set; }
    public FirestoreDb? Firestore => _firestore;
    public StorageClient? Storage => _storage;
    public string? StorageBucket =>
        string.IsNullOrWhiteSpace(_settings.StorageBucket) ? null : _settings.StorageBucket;

    private void TryInitialize()
    {
        lock (_gate)
        {
            if (_initialized)
            {
                return;
            }

            _initialized = true;

            if (!_settings.Enabled)
            {
                UnavailableReason = "Firebase disabled via configuration.";
                _logger.LogInformation("Firebase integration is disabled.");
                return;
            }

            if (string.IsNullOrWhiteSpace(_settings.ProjectId))
            {
                UnavailableReason = "Firebase:ProjectId is missing.";
                _logger.LogWarning("Firebase ProjectId is not configured. Site will use fallbacks.");
                return;
            }

            if (!_settings.IsConfigured)
            {
                UnavailableReason = "Firebase credentials are not configured (User Secrets / env / ADC).";
                _logger.LogWarning(
                    "Firebase credentials required — set User Secrets, Firebase__ServiceAccountPath/Json, or GOOGLE_APPLICATION_CREDENTIALS. Using local fallbacks.");
                return;
            }

            try
            {
                var credential = ResolveCredential();
                if (FirebaseApp.DefaultInstance is null)
                {
                    var options = new AppOptions
                    {
                        Credential = credential,
                        ProjectId = _settings.ProjectId,
                    };
                    FirebaseApp.Create(options);
                }

                _firestore = new FirestoreDbBuilder
                {
                    ProjectId = _settings.ProjectId,
                    Credential = credential,
                }.Build();

                _storage = StorageClient.Create(credential);
                IsAvailable = true;
                _logger.LogInformation("Firebase initialized for project {ProjectId}.", _settings.ProjectId);
            }
            catch (Exception ex)
            {
                // Never log credential contents.
                IsAvailable = false;
                UnavailableReason = "Firebase credentials could not be resolved or initialization failed.";
                _logger.LogError(ex, "Firebase initialization failed. Falling back to local content.");
            }
        }
    }

    private GoogleCredential ResolveCredential()
    {
        if (!string.IsNullOrWhiteSpace(_settings.ServiceAccountJson))
        {
            using var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(_settings.ServiceAccountJson));
            return CredentialFactory.FromStream<ServiceAccountCredential>(stream).ToGoogleCredential();
        }

        if (!string.IsNullOrWhiteSpace(_settings.ServiceAccountPath))
        {
            var path = Environment.ExpandEnvironmentVariables(_settings.ServiceAccountPath);
            if (!File.Exists(path))
            {
                throw new FileNotFoundException("Firebase service account file was not found.", path);
            }

            using var stream = File.OpenRead(path);
            return CredentialFactory.FromStream<ServiceAccountCredential>(stream).ToGoogleCredential();
        }

        // Application Default Credentials / GOOGLE_APPLICATION_CREDENTIALS
        return GoogleCredential.GetApplicationDefault();
    }

    public void Dispose()
    {
        _storage?.Dispose();
    }
}
