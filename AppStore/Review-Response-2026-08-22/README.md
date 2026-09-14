# Maren App Review re-submission package — build 8 candidate

Updated for Maren `1.1.0 (8)` on 2026-08-24.

This folder is a preparation package for the next App Store review submission. It is deliberately conservative: anything that has not been completed on the exact build-8 candidate is marked `PENDING` and must not be described as completed in App Store Connect or in the reviewer reply. Simulator automation evidence is reported separately and does not replace physical-device evidence.

## Package contents

- `01-Apple-Review-Reply-EN.md` — English Review Information response covering Apple’s requested items.
- `02-Physical-Device-Recording-Plan-ZH.md` — Chinese one-take physical-device recording script.
- `03-Resubmission-Checklist-ZH.md` — build, privacy, IAP, metadata, recording, and submission gate checklist.
- `04-Content-Rights-Declaration-Template-EN.md` — rights and authorization declaration template; requires developer verification and signature.
- `05-Test-Matrix.csv` — device, OS, build, permission, IAP, and feature evidence matrix.
- `06-Full-Functional-Audit-ZH.md` — feature-by-feature audit and review-risk register.
- `07-ASC-Review-Notes-EN.txt` — exact English Review Notes saved in App Store Connect, organized as requested items 2–8.

## Candidate and evidence boundary

- Candidate: Maren `1.1.0 (8)`.
- Build 8 automated tests: **completed locally** — 397/397 passed, 0 failures; Xcode 26.6 (17F113), Vela Review iPhone 17 simulator on iOS 26.5; `Evidence/Build8/Vela-1.1.0-8-full-tests.xcresult`.
- Release iOS and VelaWatch scheme builds: **completed locally** for four targets.
- Build 8 archive and IPA: **completed locally** — `../Builds/Maren-1.1.0-8/Maren-v1.1.0-b8.xcarchive` and `../Builds/Maren-1.1.0-8/Maren.ipa`.
- IPA SHA-256: `acdb4c97fd294939e758ea499b25b9149d80c74cb22fb9f681f72d6d5526515c`.
- Release signing: **completed locally** with Apple Distribution / Jun Yu / team `255R6QQR97`; all four bundles are `1.1.0 (8)`, use App Group `group.cd.cc.vela`, and have `get-task-allow=false`; strict/deep code-sign verification passed. The main app has HealthKit enabled.
- App Store Connect upload: **completed** via Xcode’s official export/upload at 2026-08-24 05:00 Pacific. The upload log reported `EXPORT SUCCEEDED`, `Upload succeeded`, `Uploaded Vela`, and `Uploaded package is processing`.
- App Store Connect IAP setup: **completed** — Maren Premium group plus monthly (`$3.99`), yearly (`$29.99` with an eligible-new-subscriber seven-day introductory free trial), and lifetime (`$69.99`) products have localization, review notes, review screenshots, pricing, and territory availability configured. All four items are present in the Draft Submission.
- App Store Connect metadata: **completed and saved** — description, promotional text, keywords, support/marketing/privacy/terms URLs, review notes, app privacy (`Data Not Collected`), categories, content rights, age rating, and free-app pricing/availability were reviewed. Accessibility declarations are saved as drafts because ASC does not allow publishing them before the first released version.
- App Store Connect processing and build-8 selection: **in progress** — upload succeeded and ASC Build Uploads shows `1.1.0 (8)` processing. Replace this line only after Build 8 is `VALID` and selected on iOS app version `1.1.0`.
- Sandbox/TestFlight purchase, restore, and eligible seven-day trial: `PENDING`.
- Physical recording on the exact candidate: `PENDING`.
- Physical-device list confirmed by the developer: iPhone Air on iOS 26.6.1 and iPhone 12 on iOS 26.6. Because the binary advanced from build 7 to build 8 for the O1 performance fix, both devices must re-confirm the exact Build 8 before submission. The final Apple-requested recording should use the iPhone Air on iOS 26.6.1 (or the latest public OS available on the recording date).
- The current Vela Review iPhone 17 / iOS 26.5 simulator run is build-8 automated evidence only; it does not replace the required physical-device test or recording. Earlier build-7 and 286/379-test results remain historical evidence and are not used for the build-8 freeze.

## Product and entitlement boundary

Maren is local-first. It records periods, symptoms, mood, body observations, medication routines, reproductive-test selections, contraception context, and notes on the device. The optional Perimenopause mode provides a free descriptive 30-day/90-day record summary. Premium is a separate layer for advanced on-device insights, deeper trends, cycle comparison, correlation exploration, advanced reminders, customizable report options, additional accent themes, and unlimited custom trackers.

The three products are:

- `cd.cc.vela.premium.monthly` — auto-renewable one-month subscription; no trial is configured in the current StoreKit configuration.
- `cd.cc.vela.premium.yearly` — auto-renewable one-year subscription; eligible new subscribers may receive Apple’s configured seven-day introductory free trial, followed by automatic annual renewal at the localized StoreKit price.
- `cd.cc.vela.premium.lifetime` — non-consumable, one-time payment with permanent Premium access.

Prices, tax, currency, eligibility, and final billing text are controlled by Apple’s storefront and must be verified in the actual review environment.

## Do not submit until

1. Install, test, and record the exact `1.1.0 (8)` candidate on the iPhone Air running iOS 26.6.1 or the latest public OS available on the recording date.
2. Begin at the Home Screen and show the normal core flow, local search, permissions, deletion, paywall, restore/trial wording, and device integrations described in the script.
3. Upload the recording to App Review Information and verify it does not expose real health, Apple ID, or payment data.
4. Re-open the five-item Draft Submission, verify it shows iOS app `1.1.0 (8)`, and let the developer click the final Submit for Review button.

The IAP products, annual seven-day introductory offer, review metadata, public URLs, app privacy, pricing, exact items 2–8 Review Notes, and all five Draft Submission items are configured in ASC. Exact Build 8 physical-device re-testing, Sandbox/TestFlight purchase verification, and the requested recording remain pending, and final submission remains reserved for the developer. The local build-8 test, build, archive, IPA, signing, and upload evidence listed above is complete.
