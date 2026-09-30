namespace Mevora.Admin.Web.Resources;

/// <summary>
/// Marker for the console's single string table.
///
/// Keys are the English text itself, so English needs no resource file: a key
/// that is not translated renders as written. Turkish lives in
/// SharedResource.tr.resx. Stored codes (USER_REPORT, manual_review…) are
/// looked up as "code:&lt;value&gt;" and fall back to a readable form of the code.
/// </summary>
public sealed class SharedResource;
