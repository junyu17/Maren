# Maren App Review resubmission package - ARCHIVED

> Historical build 2 package. Do not send these files to Apple. The current build 3 package is `AppStore/Review-Response-2026-08-21/`.

Prepared on: 2026-08-14  
Project: `/Users/jun/Documents/Vela`  
Public app name: **Maren**  
Bundle ID: `cd.cc.vela`  
Audited build settings: version `1.0.0`, build `2` (build `1` was superseded)

## Package contents

1. `01-Apple-Review-Reply-EN.md` — professional English reply covering every item requested by App Review.
2. `02-Physical-Device-Recording-Plan-ZH.md` — one-take physical-device recording plan and shot checklist.
3. `03-Resubmission-Audit-and-Checklist-ZH.md` — verified feature inventory, blockers, test status, and upload checklist.
4. `04-Content-Rights-Declaration-Template-EN.md` — optional declaration if Apple asks about rights to the app's copy, quotes, or artwork.
5. `05-Test-Matrix-Template.csv` — test evidence sheet to complete before sending the reply.

## Do not send yet

The English reply is intentionally marked with a small number of `[FINALIZE BEFORE SENDING]` fields. Do not remove those markers until the physical-device, TestFlight/Sandbox IAP, and rights checks in `03-Resubmission-Audit-and-Checklist-ZH.md` are complete.

## Status of the previous submission blockers

1. **CloudKit health-data sync — RESOLVED (2026-08-14).** Build `1` stored period, mood, symptom, medication, and other health records in an optional CloudKit private database when iCloud sync was enabled, which conflicts with App Review Guideline 5.1.3(ii) ("may not store personal health information in iCloud"). The remediation removed all CloudKit/iCloud code, entitlement, Settings toggle, and claims; build `2` stores all health data only in a local on-device SwiftData store with no cloud sync. The English reply and audit/checklist describe the fixed build. Reference: <https://developer.apple.com/app-store/review/guidelines/#health-and-health-research>
2. **Physical-device recording — PENDING.** The connected iPhone 12 on iOS 26.6 could not be used because Xcode reported that the device needed to be unlocked. A simulator build and a signed Release archive succeeded, but these are not substitutes for Apple's requested physical-device recording. This remains an explicit pre-send to-do.

## Verified technical baseline

- iOS Simulator build: passed on iPhone 17 simulator, iOS 26.5.
- Fresh launch: visually verified; the app opens to the English onboarding flow.
- Release archive: succeeded with the iOS app, Widget extension, and Watch app embedded.
- Archive signature structure: passed `codesign --verify --deep --strict`.
- Archive versions: iOS app, Widget, and Watch app are all `1.0.0 (2)`.
- Privacy manifests: present in the app, Widget, and Watch bundles.
- Hosted website, privacy policy, and terms URLs: HTTP 200.
- CloudKit entitlement: removed from `project.yml`, `Vela/Vela.entitlements`, and Signing & Capabilities (verified in repo).
- Final archive entitlement inspection: App Groups + HealthKit only; no iCloud/CloudKit entitlement.
- Localization catalog audit: English and Simplified Chinese complete (brand name `Maren` intentionally unchanged); both resources compiled into the final archive.
- Physical device identified: iPhone 12, iOS 26.6. It briefly appeared as paired/available, but the build 2 install failed with `com.apple.dt.RemotePairingError error 4` (tunnel connection failed), so physical runtime testing remains pending.
