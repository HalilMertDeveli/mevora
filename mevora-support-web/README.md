# Mevora Support Website

Bağımsız ASP.NET Core 8 Razor Pages sitesi — Mevora mobil uygulamasının resmi destek, yardım ve tanıtım yüzü.

```text
Mevora/
├── lib/ android/ ios/ ...     ← Flutter mobil app (dokunulmaz)
└── mevora-support-web/        ← bu proje
```

```text
Flutter App → Firebase (client)
mevora-support-web → ASP.NET Core → Admin SDK → Firestore/Storage
                              → Email Service → SMTP
```

## Local development

```powershell
cd mevora-support-web
dotnet restore
dotnet build
dotnet run --launch-profile http
```

`http://localhost:5129`

### Firebase (User Secrets)

```powershell
dotnet user-secrets set "Firebase:ProjectId" "<project-id>"
dotnet user-secrets set "Firebase:StorageBucket" "<bucket>.appspot.com"
dotnet user-secrets set "Firebase:ServiceAccountPath" "C:\secure\service-account.json"
```

### Email / SMTP (User Secrets)

```powershell
dotnet user-secrets set "Email:Enabled" "true"
dotnet user-secrets set "Email:Host" "smtp.example.com"
dotnet user-secrets set "Email:Port" "587"
dotnet user-secrets set "Email:UseSsl" "true"
dotnet user-secrets set "Email:Username" "<smtp-user>"
dotnet user-secrets set "Email:Password" "<smtp-password>"
dotnet user-secrets set "Email:SenderEmail" "noreply@example.com"
dotnet user-secrets set "Email:SupportEmail" "support@example.com"
dotnet user-secrets set "Email:SendUserConfirmation" "false"
```

Production env vars: `Email__Host`, `Email__Password`, `Email__SupportEmail`, `Firebase__ProjectId`, `Site__BaseUrl`, …

**Gerçek secret/password asla Git’e koyma.**

Email yapılandırılmamışsa ticket yine Firestore’a yazılır; mail atlanır (log’lanır).

## Site configuration

| Key | Notes |
| --- | --- |
| `Site:BaseUrl` | Production origin; boşsa request host |
| `Site:SupportEmail` | Public contact display |
| `Email:SupportEmail` | Team inbox for new tickets |
| `Email:SendUserConfirmation` | Default `false` |

## Firestore

- `supportTickets` — Open/InProgress/Resolved/Closed, Low/Normal/High/Urgent
- `faqItems` — published FAQs (fallback: `Data/DefaultFaqData.cs`)

## Storage

`support/{ticketId}/{guid}.{ext}` — jpeg/png/webp, max 5 MB

## Support email flow

```text
Form → validation → Firestore ticket → team email (optional user confirmation)
```

Templates: `EmailTemplates/SupportTicketCreated.html`, `SupportTicketReceived.html`

## Routes

`/`, `/support`, `/faq`, `/privacy`, `/terms`, `/Error`, dinamik `/robots.txt`, `/sitemap.xml`

## Production Domain Setup

Domain henüz yok. Alındığında:

1. Domain satın al  
2. ASP.NET Core hosting  
3. DNS + SSL  
4. `Site__BaseUrl` / `Site__CanonicalUrl`  
5. Firebase + Email env secrets  
6. `dotnet publish -c Release`  
7. Health check, form, email, mobile link test  

## Publish

```powershell
cd mevora-support-web
dotnet publish -c Release -o ./publish
```

## Security

Antiforgery, validation, rate limit, upload checks, security headers. Email/Firebase failures do not expose stack traces to users.
