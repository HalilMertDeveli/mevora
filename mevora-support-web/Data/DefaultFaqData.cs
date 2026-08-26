using Mevora.Web.Models;

namespace Mevora.Web.Data;

public static class DefaultFaqData
{
    public static IReadOnlyList<FaqItem> Items { get; } =
    [
        new()
        {
            Id = "fallback-1",
            Question = "Mevora nedir?",
            Answer = "Mevora, ortak ilgi alanları, ilişki beklentileri ve uyumluluk sinyalleri üzerinden daha anlamlı eşleşmeler keşfetmeni sağlayan bir mobil uygulamadır.",
            Category = "general",
            Order = 1,
            IsPublished = true,
        },
        new()
        {
            Id = "fallback-2",
            Question = "Uyumluluk skoru nasıl hesaplanır?",
            Answer = "Compatibility Engine; profil bilgileri, ortak ilgi alanları, ilişki beklentileri ve soru-cevap yanıtlarını birlikte değerlendirerek bir uyumluluk yüzdesi üretir. Sonuç kesin bir yargı değil, keşif için bir rehberdir.",
            Category = "compatibility",
            Order = 2,
            IsPublished = true,
        },
        new()
        {
            Id = "fallback-3",
            Question = "Hesabımı nasıl silebilirim?",
            Answer = "Uygulama içinde Ayarlar → Hesap → Hesabı Sil yolunu kullanabilirsin. Silme işlemi kalıcıdır; bazı kayıtlar yasal zorunluluklar nedeniyle sınırlı süre tutulabilir.",
            Category = "account",
            Order = 3,
            IsPublished = true,
        },
        new()
        {
            Id = "fallback-4",
            Question = "Mesajlar güvenli mi?",
            Answer = "Eşleşmeler karşılıklı beğeni ile oluşur. Uygun cihaz ve anahtar koşullarında mesajlar uçtan uca şifrelenebilir. Güvenlik için engelleme ve bildirme araçlarını da kullanabilirsin.",
            Category = "messaging",
            Order = 4,
            IsPublished = true,
        },
        new()
        {
            Id = "fallback-5",
            Question = "Boost nedir?",
            Answer = "Boost, keşfedilebilirliğini geçici olarak artıran isteğe bağlı bir özelliktir. Satın almalar uygulama mağazası üzerinden işlenir.",
            Category = "payments",
            Order = 5,
            IsPublished = true,
        },
        new()
        {
            Id = "fallback-6",
            Question = "Destek talebi ne kadar sürede yanıtlanır?",
            Answer = "Talepler öncelik ve yoğunluğa göre incelenir. Acil güvenlik konularında mümkün olan en kısa sürede dönüş hedeflenir.",
            Category = "support",
            Order = 6,
            IsPublished = true,
        },
    ];
}
