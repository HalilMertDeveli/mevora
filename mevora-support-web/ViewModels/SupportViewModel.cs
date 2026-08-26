using System.ComponentModel.DataAnnotations;
using Mevora.Web.Models;
using Microsoft.AspNetCore.Http;

namespace Mevora.Web.ViewModels;

public sealed class SupportFormViewModel
{
    [Required(ErrorMessage = "Ad soyad zorunludur.")]
    [StringLength(80, MinimumLength = 2, ErrorMessage = "Ad soyad 2–80 karakter olmalıdır.")]
    [Display(Name = "Ad Soyad")]
    public string Name { get; set; } = string.Empty;

    [Required(ErrorMessage = "E-posta zorunludur.")]
    [EmailAddress(ErrorMessage = "Geçerli bir e-posta girin.")]
    [StringLength(120)]
    [Display(Name = "E-posta")]
    public string Email { get; set; } = string.Empty;

    [StringLength(128, ErrorMessage = "Kullanıcı ID en fazla 128 karakter olabilir.")]
    [Display(Name = "Kullanıcı ID")]
    public string? UserId { get; set; }

    [Required(ErrorMessage = "Kategori seçin.")]
    [Display(Name = "Kategori")]
    public string Category { get; set; } = string.Empty;

    [Required(ErrorMessage = "Konu zorunludur.")]
    [StringLength(120, MinimumLength = 3, ErrorMessage = "Konu 3–120 karakter olmalıdır.")]
    [Display(Name = "Konu")]
    public string Subject { get; set; } = string.Empty;

    [Required(ErrorMessage = "Açıklama zorunludur.")]
    [StringLength(4000, MinimumLength = 10, ErrorMessage = "Açıklama 10–4000 karakter olmalıdır.")]
    [Display(Name = "Açıklama")]
    public string Description { get; set; } = string.Empty;

    [Required(ErrorMessage = "Öncelik seçin.")]
    [Display(Name = "Öncelik")]
    public string Priority { get; set; } = SupportPriorities.Normal;

    [Display(Name = "Ekran görüntüsü (isteğe bağlı)")]
    public IFormFile? Screenshot { get; set; }

    public string? SelectedSupportCategory { get; set; }
}

public sealed class HomePageViewModel
{
    public SupportFormViewModel SupportForm { get; set; } = new();
    public IReadOnlyList<FaqItem> Faqs { get; set; } = [];
    public bool FaqsFromFallback { get; set; }
    public bool SubmissionSucceeded { get; set; }
    public string? SubmissionError { get; set; }
    public string? CreatedTicketId { get; set; }
}
