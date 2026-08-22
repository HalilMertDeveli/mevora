# README images

Documentation visuals for GitHub. Regenerate live auth captures with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/screenshots/build_readme_images.ps1
```

| File | Source |
| --- | --- |
| `mevora-hero.png` | `assets/images/login_background.jpg` |
| `mevora-login.png` | Android emulator capture (login welcome) |
| `mevora-register.png` | Android emulator capture (register) |
| `mevora-login-email.png` | Android emulator capture (email form) |
| `mevora-phone.png` | Android emulator capture (phone sign-in) |
| `mevora-discover-sample.png` | `assets/images/portraits/mock-08.jpg` |
| `mevora-profile-sample.png` | `assets/images/portraits/mock-02.jpg` |
| `login-hero.jpg` | Same hero asset (JPEG copy for legacy links) |
| `portrait-0N.jpg` | `assets/images/portraits/mock-0N.jpg` |

Do not commit credentials, Firebase project secrets, or real user data in screenshots.
