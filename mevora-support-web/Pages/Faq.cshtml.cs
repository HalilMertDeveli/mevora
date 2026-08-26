using Mevora.Web.Models;
using Mevora.Web.Services.Firebase;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Mevora.Web.Pages;

public class FaqModel : PageModel
{
    private readonly IFirebaseContentService _contentService;

    public FaqModel(IFirebaseContentService contentService)
    {
        _contentService = contentService;
    }

    public IReadOnlyList<FaqItem> Faqs { get; private set; } = [];
    public bool FaqsFromFallback { get; private set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        var result = await _contentService.GetPublishedFaqsAsync(cancellationToken);
        Faqs = result.Items;
        FaqsFromFallback = result.FromFallback;
    }
}
