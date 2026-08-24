# Draft response to App Review — Maren 1.1.0 (7)

> Submission status: this is a build-7 candidate response. Replace each `PENDING` item only after the corresponding evidence exists for the exact signed build `1.1.0 (7)`. The completed simulator automation and local archive/IPA evidence below do not replace physical-device recording, permissions, Watch testing, or App Store Connect evidence.

Hello App Review Team,

Thank you for reviewing Maren. The candidate described here is Maren `1.1.0 (7)`, a local-first period, symptom, mood, and personal-wellness tracker. We have included a physical-device recording plan and precise reviewer paths below. The build-7 recording remains `PENDING`. The exact IPA was uploaded through Xcode’s official export/upload flow, finished processing, and is selected for iOS app version `1.1.0`. The Maren Premium subscription group, monthly/yearly subscriptions, lifetime purchase, and eligible-new-subscriber seven-day annual introductory offer are configured in App Store Connect. The Draft Submission contains all five review items and is ready for the developer to submit after attaching the required recording.

## Build 7 local verification completed

The following local evidence has been completed for the exact `1.1.0 (7)` candidate:

- Xcode `26.6 (17F113)`; Vela Review iPhone 17 simulator on iOS `26.5`.
- Full automated test result: **395/395 tests passed, 0 failures** — `Evidence/Build7/Vela-1.1.0-7-full-tests.xcresult`.
- Release iOS scheme build and VelaWatch scheme build succeeded for all four targets.
- Archive: `../Builds/Maren-1.1.0-7/Maren-v1.1.0-b7.xcarchive`.
- Exported IPA: `../Builds/Maren-1.1.0-7/Maren.ipa`.
- IPA SHA-256: `f928a2c2b7950ed0ccb8dfe0e944ff7f84fff15379d6701724b9f5e7e7933100`.
- Signing: Apple Distribution, Jun Yu, team `255R6QQR97`; strict and deep code-sign verification passed. All four bundles report version `1.1.0 (7)`, App Group `group.cd.cc.vela`, and `get-task-allow=false`; the main app has HealthKit enabled.
- App Store Connect upload: **succeeded at 2026-08-22 10:47 Pacific** through Xcode’s official export/upload flow. The upload log reported `EXPORT SUCCEEDED`, `Upload succeeded`, `Uploaded Vela`, and `Uploaded package is processing`.
- App Store Connect processing and selection: **completed**. ASC shows iOS app `1.1.0 (7)` in the five-item Draft Submission with status **Ready for Review**; `Evidence/Build7/UI/asc-draft-build7-ready.png`.

The local artifacts and upload log do not by themselves replace physical-device evidence; ASC processing and build selection are documented separately by the saved ASC screenshot. None of this claims that the required physical iPhone recording, physical permissions, physical Apple Watch flow, or Sandbox/TestFlight purchases have been completed.

## 1. Physical-device screen recording

**Attachment:** `PENDING — Maren-App-Review-iPhoneAir-iOS26.6.1-or-latest-v1.1.0-b7.mp4`

The recording will begin on the physical iPhone Home Screen, show launching Maren, and follow a normal user flow through the core features. It will include:

- privacy onboarding and the no-account path;
- Today and Calendar, including recording and saving a period day, flow, mood, symptoms, body observations, notes, and medication check-ins;
- real-time updates after create, edit, and delete, including left-swipe deletion of user-created records;
- local custom Tracker creation, label/emoji editing, historical-key preservation, and deletion;
- the optional Perimenopause mode and its free descriptive 30-day/90-day record summary, separate from Premium advanced insights;
- Daily Stories and personalized educational cards from the local content catalog;
- Apple Health selection and authorization, including the read-only step-count and Apple Exercise Time types;
- local notification permission and reminder settings;
- App Lock using Face ID or device passcode if available on the test device;
- system / light / dark appearance choices and text-size choices;
- local global search from the main tabs, including exact navigation to a matching article, tracker, medication, daily log, or period date, and immediate disappearance of deleted results;
- Widget, App Shortcut, and paired Apple Watch quick-log paths if the physical devices are available;
- the single Maren Premium purchase screen, annual seven-day trial wording when StoreKit reports eligibility, monthly and lifetime choices, Restore Purchases, automatic-renewal disclosure, and Apple subscription-management path; and
- the final Delete All Data confirmation, with the destructive action performed only at the end of the recording on disposable test data.

The developer confirms that build 7 was tested on iPhone Air running iOS 26.6.1 and iPhone 12 running iOS 26.6. The final recording should use the iPhone Air on iOS 26.6.1 or the latest public Apple OS available on the recording date. The exact device, OS, language/region, build number, and recording date will be shown in the submission notes.

**Build-7 physical recording status: PENDING.**

## 2. Devices and operating systems tested before submission

The developer-confirmed physical test list is:

| Device | Operating system | Candidate / status |
|---|---|---|
| iPhone Air | iOS 26.6.1 | Build 7 tested |
| iPhone 12 | iOS 26.6 | Build 7 tested |
| Vela Review iPhone 17 simulator | iOS 26.5 | Build-7 automated local evidence: 395/395 passed, 0 failures; not a substitute for physical-device evidence |
| Physical Apple Watch | OS and model to be recorded | Build-7 paired-device test; `PENDING` |

The build-7 archive, IPA, automated test result, successful upload, ASC processing, build selection, five-item Draft Submission, and developer-confirmed physical-device list are recorded above. The final physical recording remains pending. Historical 286/379 simulator test counts are not used as build-7 evidence.

Maren supports iOS 17.0 and later. The final submission notes will identify the actual OS versions tested rather than describing an unverified device as “latest.”

## 3. Functions, target audience, problem, and value

Maren is for adults who want a private, user-controlled record of periods, symptoms, mood, body observations, medication routines, reproductive-test choices, contraception context, and related wellness notes. It is particularly useful for people with irregular cycles or people who want to observe a Perimenopause context without sending sensitive records to a developer-operated server.

Maren helps a user:

- record periods and flow in a Calendar and history view;
- record daily mood, energy, pain, sleep, weight, basal body temperature, spotting, notes, medication check-ins, and built-in or custom Trackers;
- record ovulation-test and pregnancy-test selections as records only, without interpreting them;
- record a contraception method locally, with an optional local pill reminder and no effectiveness or missed-dose claim;
- choose Apple Health types to import or write back, with sleep analysis, step count, and Apple Exercise Time read-only;
- view a free Perimenopause record summary with descriptive 30-day and 90-day facts from the user’s own records;
- browse the local education library and receive Daily Stories / personalized educational cards selected on-device;
- view Premium advanced insights, deeper trends, cycle comparison, correlation exploration, advanced reminders, customizable report options, additional accent themes, and unlimited custom Trackers;
- use Widget, App Shortcuts, and the optional Apple Watch companion for quick logging and summaries; and
- export, back up, lock, and delete local records.

Maren is not a medical device and does not diagnose, treat, cure, or prevent a disease. It does not provide medical advice, a fertility guarantee, ovulation interpretation, safe-period calculation, contraception effectiveness guidance, pregnancy prevention, or clinical decision support. Predictions and summaries are descriptive estimates from user-entered data and may be inaccurate.

## 4. Setup and access instructions

No Maren account, registration, login, email address, phone number, invitation, organization membership, or sample file is required. There are no reviewer credentials.

Recommended reviewer path:

1. Install and launch Maren. Complete or skip onboarding.
2. If desired, open the isolated **Sample Experience** from onboarding or **Settings > Try Sample Experience**. It is read-only and does not write to the user’s real database.
3. Open **Today**, use the Calendar/date control, and open **Symptoms & Trackers**. Search a built-in Tracker, add a custom Tracker, and save a sample daily record.
4. Open the **Perimenopause** record view from **Settings > Tracking context**, then open **Trends > Perimenopause record summary**. Select the 30-day and 90-day windows. This free view shows coverage and recorded facts; it is not a diagnosis.
5. Return to **Today** to view the Daily Story / personalized educational card, or open **Settings > Library** to search the local education catalog.
6. Open **Calendar**, add a period day and flow, and verify the history and prediction cards update. The Calendar remains both a display and recording surface.
7. Use the search button from **Calendar, Today, Trends, Library, or Settings**. Search local articles, built-in/custom Trackers, medications, daily logs, or period dates, then select a result to open the exact item/date. Edits and deletions update results immediately; search is entirely on-device.
8. Open **Settings > Apple Health**, choose individual types, and authorize only after selecting the feature. The seven selectable types are menstrual flow, body mass, sleep analysis, basal body temperature, intermenstrual bleeding, step count, and Apple Exercise Time.
9. Open **Trends** and select the consolidated **Maren Premium** card, or open **Settings > Maren Premium**. The same purchase screen is also reachable from **Settings > Pro Advanced Reminders** and the free custom-Tracker limit.
10. Review **Restore Purchases**, legal links, and Apple’s subscription-management link. Do not use real personal data for destructive testing.
11. At the end, use disposable sample records to demonstrate left-swipe deletion and **Settings > Delete All Data**.

### Accounts, login, and account deletion

Not applicable. Maren has no developer-managed account system, registration, login, cloud profile, or server-side account. Local data deletion is available at **Settings > Delete All Data**. Apple subscriptions remain managed by Apple in the user’s Apple ID subscription settings.

### User-generated content, reporting, and blocking

Maren’s user-generated content consists of private local notes, medication names, custom Tracker labels/emojis, and personal records. It has no public profiles, feed, comments, messaging, sharing community, social discovery, or other public UGC. Reporting and user-blocking mechanisms are therefore not applicable. The recording will demonstrate left-swipe deletion of local user content.

## 5. Sensitive data and device capabilities

All permissions are optional and requested only from the related user action:

- **Apple Health / HealthKit:** **Settings > Apple Health**. The user selects individual types. Maren may read/write menstrual flow, body mass, basal body temperature, and intermenstrual bleeding when selected. Sleep analysis, step count, and Apple Exercise Time are read-only imports. Maren never sends HealthKit data to a developer-operated server.
- **Notifications:** reminder settings and the local contraception record. Notifications are scheduled locally; there is no developer push server.
- **Face ID / Touch ID / device passcode:** optional **Settings > Privacy > App Lock**, used only to unlock local records.
- **App Groups, WidgetKit, App Intents / Shortcuts, and WatchConnectivity:** local quick-log and summary handoff between the app, extensions, and a paired Apple Watch.

Maren does not request location, contacts, camera, microphone, photos, Bluetooth, advertising identifier, Motion & Fitness, or App Tracking Transparency access.

## 6. External services, tools, and platforms

Maren has no developer-operated backend, CloudKit/iCloud health-data sync, third-party authentication, analytics, advertising, data broker, AI service, social network, or third-party payment processor.

The app uses Apple platform services and local frameworks:

- **SwiftData:** local on-device storage;
- **StoreKit 2 / App Store:** product display, purchase processing, verified entitlement state, Restore Purchases, and Apple-managed subscriptions;
- **HealthKit / Apple Health:** optional user-selected read/write health types and read-only steps/exercise/sleep imports;
- **UserNotifications:** local reminders;
- **LocalAuthentication:** optional app lock;
- **App Intents / Shortcuts and WidgetKit:** quick logging and local widget presentation;
- **App Groups:** protected local handoff between the app and extensions;
- **WatchConnectivity:** paired-device quick-log and summary exchange; and
- **Files/document picker:** user-directed raw export and encrypted backup import/export.

Today Status, Perimenopause summaries, correlations, Premium insights, Story selection, and educational cards are computed from local data on the device. Static support, privacy, and terms pages do not receive health records.

## 7. Regional differences

Core features and data handling are intended to be consistent across supported regions. The app includes English and Simplified Chinese localization selected by the operating system. There is no region-specific clinical service, community, or third-party health catalog.

StoreKit product availability, price, currency, tax, introductory-offer eligibility, billing text, and subscription storefront may vary by the user’s Apple storefront. System permission dialogs and language follow the device settings. Apple Health availability also depends on the device, OS, and the user’s Health permissions.

## 8. Regulated industry and third-party material

Maren does not provide medical diagnosis, treatment, telehealth, pharmacy, laboratory, insurance, fertility, contraceptive, or clinical services. It is a personal tracking and insight tool, not a medical device. No healthcare credential is required to use the app.

The developer does not distribute a licensed third-party media catalog. Educational articles, Daily Stories, supportive messages, interface copy, icons, and screenshots are original, commissioned, or lawfully licensed by the developer. The app does not operate a regulated clinical service, so no additional credentials or authorization documents are required for its stated functionality.

## 9. In-App Purchases

Maren Premium has one entitlement level and three products:

| Product | Product ID | Type | User receives |
|---|---|---|---|
| Maren Premium Monthly | `cd.cc.vela.premium.monthly` | Auto-renewable subscription, 1 month | Premium while the subscription is active; Apple renews automatically unless cancelled |
| Maren Premium Yearly | `cd.cc.vela.premium.yearly` | Auto-renewable subscription, 1 year | Premium while the subscription is active; eligible new subscribers may see a seven-day introductory free trial, then automatic annual renewal |
| Maren Premium Lifetime | `cd.cc.vela.premium.lifetime` | Non-consumable | Permanent Premium access after a one-time payment; no renewal |

Prices and currency are supplied by StoreKit. The current local StoreKit configuration has a seven-day free-trial introductory offer on the yearly subscription only. The paywall displays the trial wording only when Apple reports that the user is eligible. Monthly has no trial configured in the current configuration.

The purchase screen is reachable from:

1. **Trends > Maren Premium** consolidated card;
2. **Settings > Maren Premium > Upgrade Maren Premium**;
3. **Settings > Pro Advanced Reminders**; and
4. the free custom-Tracker limit when the user tries to add another item.

On the purchase screen, the user selects Monthly, Yearly, or Lifetime, reviews the localized price and billing period, and taps the purchase button. The annual plan may show **7 days free** for an eligible user. The screen explains that subscriptions automatically renew, the Apple ID is charged at confirmation and renewal, the user can cancel in Apple subscription settings, and the lifetime product is a one-time purchase. **Restore Purchases** calls Apple’s sync path and is available on the paywall and from Settings.

**Build-7 Sandbox/TestFlight purchase and restore evidence: PENDING.**

## 10. Privacy and legal links

- Privacy Policy: <https://junyu17.github.io/Maren/privacy.html>
- Terms of Use: <https://junyu17.github.io/Maren/terms.html>
- Support / product site: <https://junyu17.github.io/Maren/>

The Privacy Policy states that HealthKit step count and Apple Exercise Time are read-only and that Maren has no developer-operated server receiving health data.

Please let us know if any additional test instructions or documentation would be helpful. Thank you for reviewing Maren.

Sincerely,

Jun Yu — reviewer contact details are saved in App Store Connect Review Information.
