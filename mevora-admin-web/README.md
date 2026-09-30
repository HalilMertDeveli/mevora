# mevora-admin-web

The MEVORA Trust & Safety console — a private, staff-only ASP.NET Core 8
Razor Pages app. It is a UI and session layer (BFF) over the admin commands in
`functions/src/admin`; it holds no Firebase server credential and never talks
to Firestore. Architecture, roles and security model:
[`docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md`](../docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md).

Not to be confused with `mevora-support-web`, the public support site.

## Run locally against the emulators

From the repo root:

```powershell
npm --prefix functions ci
npm --prefix functions run build
npx firebase emulators:start --config firebase.qa.json --only auth,firestore,functions,storage --project mevora-d6ed0
```

In a second terminal, seed the console's QA world (emulator only — it refuses
anything else):

```powershell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
$env:FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199"
node tool/seedEmulatorAdminQa.cjs
```

Then start the console:

```powershell
dotnet run --project mevora-admin-web --launch-profile emulator
```

Open http://localhost:5310 and sign in with a seeded staff account
(`super@`, `tsa@`, `senior@`, `moderator@`, `support@mevora.test`; the
emulator-only password is in `tool/seedEmulatorAdminQa.cjs`).

`appsettings.Development.json` points at the default emulator ports and uses
the emulator-only BFF secret that the Functions emulator falls back to. In the
emulator, MFA is not enforced (the Auth emulator cannot complete TOTP
enrolment) and the header says so; production always requires it.

Automated end-to-end check of the whole console against the running suite:

```powershell
$env:ADMIN_WEB_URL = "http://localhost:5310"
node tool/adminConsoleSmoke.cjs
```

## Language

The console speaks Turkish and English. Each staff member picks one with the
TR / EN switch in the header (or on the sign-in page); the choice is kept in a
culture cookie for a year. Without a choice the console uses `AdminWeb:DefaultCulture`
(`tr` unless set to `en`).

- English text is the key; Turkish lives in `Resources/SharedResource.tr.resx`.
  A missing entry shows English, never an error.
- Stored codes (statuses, reasons, roles, audit events) are translated for display
  through `code:<CODE>` entries; forms still send the raw code to the backend.
- `LocalizationTests.Every_console_string_has_a_Turkish_translation` fails when a
  new `L["…"]` string has no Turkish entry — add it to the resx in the same change.

## Tests

```powershell
dotnet test mevora-admin-web.Tests
```

## Configuration (production)

| Setting | Value |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `AdminWeb__ProjectId` | `mevora-d6ed0` |
| `AdminWeb__WebApiKey` | the project's Firebase Web API key (public) |
| `AdminWeb__FunctionsBaseUrl` | `https://europe-west1-mevora-d6ed0.cloudfunctions.net` |
| `AdminWeb__BffSharedSecret` | same value as the `ADMIN_BFF_SHARED_SECRET` functions secret |
| `AdminWeb__DefaultCulture` | optional: `tr` (default) or `en` |

Startup refuses a production configuration that points at an emulator, uses
the emulator secret, or calls Functions over plain HTTP.
