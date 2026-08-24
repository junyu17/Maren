# Maren App Review re-submission package

Prepared for the upcoming Maren `1.1.0 (5)` candidate on 2026-08-22.

This package describes the implemented 1.1 features and the evidence that is
still required before submission. The signed candidate and local test evidence
are recorded below; the physical-device recording, App Store Connect, and any
actual Sandbox/TestFlight results remain separate evidence.

Files:

- `01-Apple-Review-Reply-EN.md`: professional English response and reviewer path.
- `02-Physical-Device-Recording-Plan-ZH.md`: one-take physical-device script for 1.1.
- `03-Resubmission-Checklist-ZH.md`: Chinese build, privacy, IAP, metadata, and evidence checklist.
- `04-Content-Rights-Declaration-Template-EN.md`: optional declaration requiring developer verification and signature.
- `05-Test-Matrix.csv`: device/OS evidence; pending rows must not be changed to PASS without evidence.
- `06-Full-Functional-Audit-ZH.md`: Chinese code-path and review-risk audit for 1.1.

Current evidence boundaries:

1. The available physical Jufei iP12 (iPhone 12) was observed at iOS 26.6 (23G71) without a functional app test. A build-5 install attempt on 2026-08-22 could not establish a CoreDevice connection, so no installation result is claimed. Apple released iOS 26.6.1 on 2026-08-17; reconnect, unlock, and upgrade it before recording and rerun the required flow. Official notice: <https://support.apple.com/en-us/148282>.
2. The iPhone Air was unavailable and was not tested. It must not be used as a recording device or described as tested.
3. The final `1.1.0 (5)` candidate has a recorded iPhone 17 / iOS 26.5 simulator run of 286 automated tests with 0 failures. This remains simulator-only and does not replace physical-device evidence. The preserved result is `Evidence/Vela-v1.1-final-tests-286.xcresult`.
4. Independent Maestro coverage passed Education, Contraception, Reproductive tests, HealthKit English localization, Simplified Chinese Today/Tracker layout, and the final English Trends/Library UI 2.0 flow. The covered English flow showed no mixed Chinese/English strings. Screenshots are preserved under `Evidence/Screenshots/vela-ui2-*`.
5. Final local artifacts are present under `../Builds/Maren-1.1.0-5/`: signed archive `Maren-v1.1.0-b5.xcarchive` and exported App Store IPA `Maren.ipa`; App Store export succeeded. All four bundles are `1.1.0 (5)`, release signing/profile includes `group.cd.cc.vela`, the main app has HealthKit, and `get-task-allow=false`.
6. The user-selected Perimenopause 30/90 record summary is available without Premium. Premium is offered separately through one consolidated Trends card for advanced insights, mood trends, tracker frequency, cycle comparison, and correlation exploration.
7. No final physical recording, physical purchase, HealthKit authorization, notification authorization, Face ID flow, Apple Watch flow, or App Store Connect upload is claimed as completed in this package. Only actual evidence may change those rows.

Submission blockers requiring developer or App Store Connect access:

1. Upgrade the available Jufei iP12 (iPhone 12) to iOS 26.6.1 or the current public release, install the exact `1.1.0 (5)` candidate, and record the full v1.1 flow from **Settings > Tracking context > Perimenopause** and **Settings > Library**.
2. Complete the physical recording only after the iPhone 12 upgrade; show the free Perimenopause 30/90 record summary, then separately show the consolidated Premium card, subscription information, and purchase/restore paths.
3. Complete and record Sandbox/TestFlight purchase and restore tests for monthly, yearly, and lifetime products if those results are to be stated in Review Information.
4. Complete the Apple Health, notifications, Face ID, export/backup, deletion, and accessibility checks on the physical device.
5. Confirm content ownership/licensing, attach IAP review screenshots, select build `1.1.0 (5)`, and complete App Privacy, age-rating, and content-rights answers. Do not describe App Store Connect upload as complete until it has happened.
