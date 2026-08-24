# Draft response to App Review — Maren 1.1.0 (5)

> Submission note: replace the recording placeholder and pending evidence only after the exact signed `1.1.0 (5)` candidate has been installed and tested. This response does not claim physical-device purchase, upload, authorization, or Apple Watch completion without attached evidence.

Hello App Review Team,

Thank you for reviewing Maren. The candidate under review is Maren `1.1.0 (5)`. Maren is a local-first period, symptom, mood, and personal-wellness tracker. The information below describes the implemented features and the reviewer path without presenting wellness statistics as medical conclusions.

## 1. Physical-device screen recording

Attachment: `[Maren-App-Review-iPhone12-iOS26.6.1-v1.1.0-b5.mp4 — attach after recording]`

The available physical Jufei iP12 (iPhone 12) was last observed at iOS 26.6 (23G71), and that observation did not include an app installation or functional test. Apple released iOS 26.6.1 on August 17, 2026. Before recording, we will update the iPhone 12, record the actual installed OS/build, install the exact candidate, and attach the one-take recording. Apple’s release notice is available at <https://support.apple.com/en-us/148282>.

The iPhone Air was unavailable and was not tested. It is not used as evidence or as the recording device.

The recording plan shows:

- launch from the physical iPhone Home Screen, privacy onboarding, no-account path, and the isolated read-only Sample Experience;
- Today Status, which presents up to three device-generated observations from values the user recorded;
- the 106 built-in Tracker entries grouped into 10 searchable categories, plus local custom trackers;
- daily mood, energy, pain, sleep, weight, basal-body-temperature, spotting, note, medication, and check-in logging;
- ovulation-test choices, the independent manual-ovulation entry, and pregnancy-test choices as records only;
- local contraception method recording and the optional pill-only daily reminder setting, with neutral no-effectiveness wording;
- the local Library and the Daily Story/personalized educational card;
- the user-selected Perimenopause mode and the free descriptive 30-day/90-day recorded-trend summary;
- Apple Health’s seven selectable types, including read-only sleep analysis, step count, and Apple Exercise Time;
- existing Calendar, cycle-history, export, encrypted-backup, deletion, Shortcuts, Widget, and notification entry points; and
- the StoreKit purchase and Restore Purchases paths, with purchase success shown only if it is actually completed during the recorded test.

## 2. Devices and operating systems

The exact candidate and evidence must be reconciled before submission:

- Physical Jufei iP12 (iPhone 12): currently observed at iOS 26.6 (23G71), not functionally tested; upgrade to iOS 26.6.1 or the current public release before recording.
- iPhone Air: unavailable and not tested; no physical-device result is claimed.
- iPhone 17 simulator, iOS 26.5: the final `1.1.0 (5)` candidate completed 286 automated tests with 0 failures. This is simulator-only evidence, not a physical-device test. The preserved result is `Evidence/Vela-v1.1-final-tests-286.xcresult` in the submission package.
- Independent Maestro flows passed Education, Contraception, Reproductive tests, HealthKit English localization, Simplified Chinese Today/Tracker layout, and the final English Trends/Library UI 2.0 flow. The covered English flow showed no mixed Chinese/English strings.
- The signed archive and exported App Store IPA are preserved under `AppStore/Builds/Maren-1.1.0-5/`; App Store export succeeded. All four bundles are `1.1.0 (5)`, release signing/profile includes `group.cd.cc.vela`, the main app has HealthKit, and `get-task-allow=false`.
- Physical Apple Watch: no result is claimed without a completed recording and test-matrix evidence. Any simulator-only verification will be labelled simulator-only.

Maren supports iOS 17.0 and later. The attached recording will state the actual device model, OS, language/region, candidate build, and recording date. No device is described as “latest” until its OS has been checked on the recording date.

## 3. Functions, audience, problem solved, and value

Maren is for people who want a private, user-controlled record of periods, symptoms, mood, body observations, medication routines, and related wellness notes, including people with irregular cycles or people who prefer not to send sensitive records to a developer-operated server.

Maren helps users:

- record periods and flow with an adaptive range estimated from their own recorded history;
- record daily mood, energy, pain, sleep, weight, basal body temperature, spotting, 106 built-in Tracker options, custom trackers, notes, medications, and check-ins;
- see Today Status observations that are generated on device from values they entered;
- record ovulation-test results and pregnancy-test results without interpreting or predicting them;
- record a contraception method locally and optionally enable a daily reminder for a pill record, without effectiveness, missed-dose, diagnosis, or medical guidance;
- optionally import Apple Health data, including read-only steps and Apple Exercise Time;
- browse a local searchable knowledge base and receive a Daily Story/educational card selected from the user’s own local context;
- opt in to a Perimenopause life-stage mode and view descriptive 30-day and 90-day recorded-trend facts; and
- export, back up, lock, and delete their local records.

Maren does not diagnose, treat, prevent, or cure a condition. It does not provide medical advice, an ovulation or fertility guarantee, a safe-period calculation, contraception effectiveness guidance, pregnancy prevention, or clinical decision support. The Perimenopause view and all Today/Tracker observations are descriptive records and statistical summaries only.

## 4. Setup and reviewer access

No Maren account, registration, login, email address, phone number, invitation, organization membership, external server, or sample file is required.

Reviewer path:

1. Install and launch Maren; complete or skip onboarding.
2. Open **Try Sample Experience** during onboarding or from **Settings > Try Sample Experience**. It is read-only and isolated from the user’s real database.
3. On **Today**, open **Symptoms & Trackers**, search for a Tracker, expand a category, and select entries. The catalog contains 106 built-in options in 10 categories; a custom item can be added from the same area.
4. Record a mood, sleep value, or Tracker and save. The **Today Status** card displays only a few device-generated observations based on those entries.
5. In the reproductive-test section, select an ovulation-test result, the independent manual-ovulation entry if desired, or a pregnancy-test result. These controls log choices only and show an explicit non-interpretation disclaimer.
6. Open **Settings > Tracking & Reminders > Contraception record**. Select a method; select **Pill** to see the optional daily reminder/time. Other methods do not retain a daily reminder. The record is stored locally.
7. Open **Settings > Library** to search or filter local educational articles. Return to **Today** to see the Daily Story/educational card selected from local context.
8. Choose **Settings > Tracking context > Perimenopause**, then open **Trends > Perimenopause summary** and switch between **30 days** and **90 days**. This descriptive record summary is available without Premium and shows coverage and recorded facts, not a diagnosis.
9. In **Settings > Apple Health**, select individual types. The app can read seven types; sleep analysis, step count, and Apple Exercise Time are read-only. Authorization is requested only after the user chooses this entry point.
10. On **Calendar**, mark a period day and flow. The app shows a personal-history estimate and clear non-medical/non-contraception wording.
11. On **Trends**, use the single consolidated **Maren Premium** card to open the purchase screen, or open **Settings > Maren Premium**. The same paywall is also reachable from **Settings > Pro Advanced Reminders** and the free custom-Tracker limit.
12. On **Calendar** or **Settings > Encrypted Backup**, review the raw export warnings, encrypted backup preview, Merge/Replace choices, and Delete All Data confirmation. Do not use Replace on real reviewer data.

Review credentials: **Not applicable; Maren has no account system.**

### Accounts and deletion

Maren does not create a developer-managed account, so registration, login, and server-side account deletion do not apply. **Settings > Delete All Data** provides a destructive confirmation and removes the local records, queues, snapshots, manual-cycle preference, and reminders derived from those records. It only attempts to remove Health samples previously written by Maren and reports when HealthKit write permission is unavailable. Apple subscriptions remain managed through the user’s App Store subscription settings.

### User-generated content

Notes, medication names, and custom Tracker labels are private local records. Maren has no public profile, community, shared feed, messaging, comments, public UGC, or social discovery service. Reporting and user-blocking systems are therefore not applicable.

## 5. Sensitive permissions and Apple Health capabilities

Each permission is optional and is requested only after the user selects the related feature:

- **Notifications:** Settings > Reminders and the local contraception record. Used for local reminders only; the app does not use a developer push server.
- **Apple Health:** Settings > Apple Health. The user selects among menstrual flow, body mass, sleep analysis, basal body temperature, intermenstrual bleeding, step count, and Apple Exercise Time. Menstrual flow, body mass, basal body temperature, and intermenstrual bleeding may be read/written when selected. Sleep analysis, step count, and Apple Exercise Time are read-only imports. Maren keeps the data on the device/Apple Health path and does not send it to a developer server.
- **Face ID / Touch ID / device passcode:** Settings > Privacy > App Lock, used only to unlock local records.

Maren does not request location, contacts, camera, microphone, photos, Bluetooth, advertising identifier, Motion & Fitness, or App Tracking Transparency access.

## 6. External services, tools, and data handling

Maren has no developer-operated backend, CloudKit/iCloud health-data sync, third-party authentication, advertising, analytics, data broker, social network, third-party payment processor, or AI service. Today Status, Tracker summaries, Daily Story selection, Perimenopause 30/90 facts, correlations, and Premium insights are computed locally.

Maren uses Apple frameworks for local or user-directed functionality:

- **SwiftData:** local on-device record storage.
- **StoreKit 2 / App Store:** product display, purchase processing, verified entitlement state, and Restore Purchases. Apple processes payment; Maren does not receive payment-card details.
- **HealthKit / Apple Health:** optional user-selected read/write health records and read-only step/exercise/sleep imports.
- **UserNotifications:** local reminders.
- **LocalAuthentication:** optional app lock.
- **App Intents / Shortcuts and WidgetKit:** quick logging and local widget presentation.
- **App Groups:** protected local handoff between the app and extensions.
- **WatchConnectivity:** paired-device quick-log and snapshot exchange.
- **Files/document picker:** user-directed raw export and encrypted backup import/export.

The website, Privacy Policy, and Terms are static support/legal pages. They do not receive health records or provide tracking functionality.

## 7. Regional consistency and content

Maren’s features, Tracker behavior, local Library, Daily Story logic, disclaimers, and data boundaries are intended to be the same across enabled regions. English and Simplified Chinese localizations are selected by the operating system. Independent Maestro coverage passed the English HealthKit and Trends/Library flows plus the Simplified Chinese Today/Tracker layout; the covered English flow showed no mixed Chinese/English strings. There is no region-specific clinical, community, or third-party health catalog.

StoreKit product names, prices, currency, tax, subscription availability, and billing periods are returned by Apple’s storefront and may vary by region. System permission dialogs follow the device language and region.

## 8. Regulated services and protected material

Maren is not a medical device and does not provide diagnosis, treatment, clinical care, telehealth, insurance, pharmacy, laboratory, research-participant, fertility, or contraceptive services. No healthcare credential or medical license is required to use it.

Maren does not distribute a licensed third-party media catalog. The developer must separately confirm that the icon, screenshots, interface copy, educational copy, and supportive-message/quote library are original, commissioned, licensed, or otherwise lawfully usable. The supplied rights declaration is a template and must not be submitted unsigned or unverified.

## 9. In-App Purchases and navigation

Maren Premium uses one verified StoreKit entitlement. The product IDs are:

| Product | Type | Product ID | Price | Access |
|---|---|---|---|---|
| Maren Premium Monthly | Auto-renewable subscription, 1 month | `cd.cc.vela.premium.monthly` | StoreKit localized | Premium while active |
| Maren Premium Yearly | Auto-renewable subscription, 1 year | `cd.cc.vela.premium.yearly` | StoreKit localized | Premium while active |
| Maren Premium Lifetime | Non-consumable | `cd.cc.vela.premium.lifetime` | StoreKit localized | Permanent Premium |

The price and billing-period text are taken from StoreKit, not hard-coded. Monthly and yearly products should remain in the same subscription group and entitlement level in App Store Connect.

The purchase screen is reachable from:

1. The single consolidated **Maren Premium** card on **Trends**, covering advanced insights, mood trends, tracker frequency, cycle comparison, and correlation exploration.
2. **Settings > Maren Premium > Upgrade Maren Premium**.
3. **Settings > Pro Advanced Reminders**.
4. The free-tier custom Tracker limit when adding a fourth custom item.

The paywall displays the localized products, automatic-renewal/cancellation disclosure, Privacy Policy, Terms of Use, Manage Subscription, and Restore Purchases. A second restore entry is available from **Settings > Maren Premium > Restore Purchases**. The candidate’s actual purchase/restore result must be documented from real Sandbox/TestFlight evidence; this package does not claim that result in advance.

## 10. Review links

- Privacy Policy: <https://junyu17.github.io/Maren/privacy.html>
- Terms of Use: <https://junyu17.github.io/Maren/terms.html>
- Support / product website: <https://junyu17.github.io/Maren/>

Please let us know if any further test instructions or documentation would be helpful. Thank you for reviewing Maren.

Sincerely, Jun Yu — billy.yu@me.com
`[PHONE NUMBER REQUIRED IN APP REVIEW INFORMATION]`
