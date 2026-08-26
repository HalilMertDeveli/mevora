using Mevora.Web.Models;
using Mevora.Web.Services.Firebase;
using Mevora.Web.ViewModels;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;

namespace Mevora.Web.Pages.Support;

public class IndexModel : PageModel
{
    private readonly IFirebaseSupportService _supportService;
    private readonly ILogger<IndexModel> _logger;

    public IndexModel(IFirebaseSupportService supportService, ILogger<IndexModel> logger)
    {
        _supportService = supportService;
        _logger = logger;
    }

    [BindProperty]
    public SupportFormViewModel SupportForm { get; set; } = new();

    public bool SubmissionSucceeded { get; private set; }
    public string? SubmissionError { get; private set; }
    public string? CreatedTicketId { get; private set; }

    public void OnGet()
    {
        if (!string.IsNullOrWhiteSpace(Request.Query["category"]))
        {
            SupportForm.Category = Request.Query["category"].ToString();
        }
    }

    [EnableRateLimiting("support")]
    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid)
        {
            SubmissionError = "Lütfen formdaki hataları düzeltin.";
            return Page();
        }

        if (!SupportCategories.All.Any(c => c.Value == SupportForm.Category))
        {
            ModelState.AddModelError("SupportForm.Category", "Geçerli bir kategori seçin.");
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
            ModelState.AddModelError("SupportForm.Priority", "Geçerli bir öncelik seçin.");
            SubmissionError = "Lütfen formdaki hataları düzeltin.";
            return Page();
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
            _logger.LogWarning("Support page form failed.");
            return Page();
        }

        SubmissionSucceeded = true;
        CreatedTicketId = result.TicketId;
        ModelState.Clear();
        SupportForm = new SupportFormViewModel();
        return Page();
    }
}
