using Mevora.Web.Models;
using Mevora.Web.Services.Firebase;
using Mevora.Web.ViewModels;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;

namespace Mevora.Web.Pages;

public class IndexModel : PageModel
{
    private readonly IFirebaseContentService _contentService;
    private readonly IFirebaseSupportService _supportService;
    private readonly ILogger<IndexModel> _logger;

    public IndexModel(
        IFirebaseContentService contentService,
        IFirebaseSupportService supportService,
        ILogger<IndexModel> logger)
    {
        _contentService = contentService;
        _supportService = supportService;
        _logger = logger;
    }

    [BindProperty]
    public SupportFormViewModel SupportForm { get; set; } = new();

    public IReadOnlyList<FaqItem> Faqs { get; private set; } = [];
    public bool FaqsFromFallback { get; private set; }
    public bool SubmissionSucceeded { get; private set; }
    public string? SubmissionError { get; private set; }
    public string? CreatedTicketId { get; private set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        await LoadFaqsAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(Request.Query["category"]))
        {
            SupportForm.Category = Request.Query["category"].ToString();
            SupportForm.SelectedSupportCategory = SupportForm.Category;
        }
    }

    [EnableRateLimiting("support")]
    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        await LoadFaqsAsync(cancellationToken);

        if (!ModelState.IsValid)
        {
            SubmissionError = "Lütfen formdaki hataları düzeltin.";
            return Page();
        }

        if (!SupportCategories.All.Any(c => c.Value == SupportForm.Category))
        {
            ModelState.AddModelError(nameof(SupportForm.Category), "Geçerli bir kategori seçin.");
            SubmissionError = "Lütfen formdaki hataları düzeltin.";
            return Page();
        }

        var allowedPriorities = new[]
        {
            SupportPriorities.Low,
            SupportPriorities.Normal,
            SupportPriorities.High,
            SupportPriorities.Urgent,
        };

        if (!allowedPriorities.Contains(SupportForm.Priority))
        {
            ModelState.AddModelError(nameof(SupportForm.Priority), "Geçerli bir öncelik seçin.");
            SubmissionError = "Lütfen formdaki hataları düzeltin.";
            return Page();
        }

        if (SupportForm.Screenshot is { Length: > 0 })
        {
            if (SupportForm.Screenshot.Length > FirebaseSupportService.MaxUploadBytes)
            {
                ModelState.AddModelError(nameof(SupportForm.Screenshot), "Dosya boyutu en fazla 5 MB olabilir.");
                SubmissionError = "Lütfen formdaki hataları düzeltin.";
                return Page();
            }
        }

        var draft = new SupportTicketDraft(
            SupportForm.Name,
            SupportForm.Email,
            SupportForm.UserId,
            SupportForm.Category,
            SupportForm.Subject,
            SupportForm.Description,
            SupportForm.Priority);

        var result = await _supportService.CreateTicketAsync(draft, SupportForm.Screenshot, cancellationToken);
        if (!result.Succeeded)
        {
            SubmissionError = result.ErrorMessage ?? "Destek talebi oluşturulamadı.";
            _logger.LogWarning("Support form failed: {Message}", SubmissionError);
            return Page();
        }

        SubmissionSucceeded = true;
        CreatedTicketId = result.TicketId;
        ModelState.Clear();
        SupportForm = new SupportFormViewModel();
        return Page();
    }

    private async Task LoadFaqsAsync(CancellationToken cancellationToken)
    {
        var faq = await _contentService.GetPublishedFaqsAsync(cancellationToken);
        Faqs = faq.Items;
        FaqsFromFallback = faq.FromFallback;
    }
}
