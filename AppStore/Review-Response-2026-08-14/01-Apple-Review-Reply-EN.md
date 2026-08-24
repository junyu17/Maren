# ARCHIVED build 2 draft - do not send

> Use `AppStore/Review-Response-2026-08-21/01-Apple-Review-Reply-EN.md` for build 3.

> **FINALIZE BEFORE SENDING:** Replace every bracketed field, attach the completed physical-device recording, and ensure the reply describes the exact binary being resubmitted. The resubmitted build (`1.0.0 (2)`) has **no CloudKit and no iCloud** — all health data is stored only in a local on-device SwiftData store. Remove the physical-device and purchase markers below only after those checks actually pass.

Hello App Review Team,

Thank you for the opportunity to provide additional information about Maren. We have prepared a physical-device screen recording and the detailed review information below.

## 1. Physical-device screen recording

Attachment: **`Maren-App-Review-iPhone12-iOS26.6-v[VERSION]-b[BUILD].mp4`**

The recording was captured on a physical **iPhone 12 running iOS 26.6**, begins on the Home Screen with Maren being launched, and demonstrates the normal flow through the app's core functionality. It includes:

- Launching Maren and the first-run privacy onboarding flow.
- Recording period days and flow levels in the calendar.
- Reviewing the estimated cycle range, four cycle phases, and the in-app medical/contraception disclaimer.
- Recording mood, energy, pain, sleep, weight, symptoms, a private note, a custom tracking item, and medication adherence.
- Viewing free cycle history and the Premium feature entry points.
- Opening the Maren Premium purchase screen, reviewing the monthly, yearly, and lifetime products, showing the subscription information, completing a Sandbox/TestFlight purchase, verifying that Premium features unlock, and showing Restore Purchases.
- Requesting notification permission, Apple Health authorization, and Face ID/device-authentication access from their in-app entry points.
- Exporting the user's data and opening the in-app Delete All Data confirmation flow.

Maren does not request access to location, contacts, camera, microphone, photos, or App Tracking Transparency.

## 2. Devices and operating systems tested

The resubmitted build was tested on the following devices before submission:

- **iPhone 12 — iOS 26.6 — physical device:** full core flow, permissions, data persistence, data export/deletion, StoreKit Sandbox/TestFlight purchase and restore. `[FINALIZE BEFORE SENDING: include only after all rows pass]`
- **iPhone Air — iOS 26.6 — physical device:** layout, launch, core tracking, and purchase-screen smoke test. `[FINALIZE BEFORE SENDING: remove if not actually tested]`
- **iPhone 17 — iOS 26.5 — simulator:** clean install, English onboarding, build/launch smoke test, and UI layout verification.
- **Apple Watch [MODEL] — watchOS 26.6 — physical device:** companion launch, period quick log, mood quick log, and synchronization back to the paired iPhone. `[FINALIZE BEFORE SENDING: include only if actually tested; otherwise disclose simulator-only testing or remove the Watch claim/screenshot from the submission]`

The app's minimum supported operating system is iOS 17.0. The attached recording uses iOS 26.6, which is the latest public iOS release at the time of testing.

## 3. App functions, target audience, problem solved, and value

Maren is a privacy-first period, mood, symptom, and personal wellness tracker for people who menstruate, with particular attention to people with irregular or PCOS-related cycles and people who prefer not to place sensitive health records on a developer-operated server.

The app addresses three common problems:

1. Period predictions that assume a fixed textbook cycle and can be unhelpful for irregular cycles.
2. Difficulty seeing relationships among period history, mood, symptoms, sleep, weight, and medication routines.
3. Privacy and portability concerns around sensitive health records.

Maren provides the following value:

- Period and flow tracking in a calendar.
- Adaptive next-period estimates based on the user's own recorded cycle starts, supporting observed cycle lengths from 15 to 120 days and displaying an estimated range rather than a guarantee.
- Four-phase calendar visualization and general educational information.
- Daily mood, energy, pain, sleep, weight, symptom, custom tracker, note, medication, and adherence logging.
- Free cycle history and cycle-length charts.
- Optional on-device personalized insights and advanced charts through Maren Premium.
- Local reminders, medication schedules, widgets, Apple Watch quick logging, optional Apple Health integration, Face ID/device-authentication lock, CSV/PDF export, and complete in-app data deletion.

Maren is a personal tracking and general wellness-awareness tool. It is **not** a medical device, does not diagnose or treat any condition, does not provide medical advice, and must not be used for contraception, fertility guarantees, or pregnancy prevention. The app displays these limitations in the relevant cycle and education screens.

## 4. Setup and access instructions

No Maren account, registration, login, email address, phone number, password, organization membership, invitation code, sample file, or external hardware is required for the iPhone app's main features.

Reviewer setup:

1. Install and launch Maren.
2. Complete or skip the four onboarding pages.
3. On **Calendar**, tap a date, select a flow level, and tap **Mark as Period**. Add period starts on at least two cycles to see an automatic estimate, or enable **Settings > My Cycle > Set From My Own Experience** after recording one period day for an immediate manual estimate.
4. On **Today**, select mood, energy, pain, sleep, weight, symptoms, and/or a note, then tap **Save Today's Log**.
5. On **Trends**, review the free cycle-history and cycle-length sections. Tap any **Upgrade to Unlock** button to open Maren Premium.
6. On **Settings**, access medication and supplement tracking, custom tracking items, reminders, Apple Health, Face ID/device authentication, data deletion, and Restore Purchases.
7. On **Calendar**, tap the share icon to export the user's data as CSV files and a PDF summary. The export button becomes available after at least one period or daily record exists.

For the Apple Watch companion, pair a compatible Apple Watch, install Maren from the Watch app, open Maren on the watch, and use the period-flow or mood buttons. The record is transferred to the paired iPhone through WatchConnectivity.

### Accounts and deletion

Maren does not create or maintain a developer-managed user account, so registration, login, and account deletion are not applicable. Apple Health, if enabled, uses a system service controlled by the user and is not a Maren account.

The app nevertheless provides **Settings > Delete All Data**, which permanently deletes all local Maren period records, daily logs, custom trackers, medications, and medication-adherence records after a destructive confirmation. StoreKit subscriptions remain managed by Apple and can be cancelled in the user's App Store subscription settings.

### User-generated content

Users may enter private notes, custom tracker labels, and medication names. This content is private to the user and is not published, shared with other Maren users, or exposed through a community or messaging feature. Maren has no public or shared user-generated-content service; therefore user reporting and user blocking mechanisms are not applicable.

## 5. Sensitive permissions and device capabilities

All protected access is optional and is requested only after the user selects the corresponding feature:

- **Notifications:** Settings > Reminders > Enable Notifications. Used only for locally scheduled daily, period, PMS, phase-aware, and medication reminders.
- **Apple Health:** Settings > Apple Health > Connect Apple Health. Maren requests read/write access only for menstrual-flow records. The integration imports recent period records and writes period days that the user records in Maren.
- **Face ID / Touch ID / device passcode:** Settings > Privacy > Face ID / Passcode Lock. Used only to unlock Maren locally through Apple's LocalAuthentication framework.

The app does not request location, contacts, camera, microphone, photos, Bluetooth, motion/fitness, advertising identifier, or App Tracking Transparency permission.

## 6. External services, tools, and platforms used for core functionality

Maren does not use a developer-operated backend, CloudKit/iCloud, third-party authentication, advertising, analytics, data-broker, payment, or AI service. Personalized insights are deterministic statistical calculations performed on the device; no record is sent to a generative-AI provider. Maren never sends health data to a developer-operated or third-party server. Data leaves the app's local store only when the user explicitly exports it, connects Apple Health, or uses the paired Apple Watch companion.

The app uses the following Apple platforms:

- **StoreKit 2 / App Store:** loads products, processes purchases, validates current entitlements, and restores purchases. Apple processes payment; Maren does not receive payment-card details.
- **HealthKit / Apple Health:** optional menstrual-flow import and export, requested by the user and processed through Apple's HealthKit APIs on the device.
- **UserNotifications:** schedules local reminders on the device.
- **LocalAuthentication:** provides optional Face ID, Touch ID, or device-passcode protection.
- **WatchConnectivity:** transfers the user's period or mood quick log from the paired Apple Watch to the iPhone.
- **WidgetKit and App Groups:** displays a local snapshot in the Home Screen widget and deep-links back to the app.

The publicly hosted Maren website, Privacy Policy, and Terms of Use are provided through GitHub Pages. These pages provide support and legal information and do not deliver the app's tracking or Premium functionality.

## 7. Regional differences

Maren's functional feature set and educational content are consistent across all regions where the app is available. The app provides English and Simplified Chinese localizations; unsupported languages fall back to English.

There is no region-specific medical, community, or third-party catalog content. In-App Purchase prices, currency, taxes, and product availability may vary by App Store storefront and are displayed from StoreKit rather than hard-coded in the app. System permission dialogs also follow the device's language and regional settings.

## 8. Regulated services and protected third-party material

Maren does not provide clinical care, diagnosis, treatment, telehealth, insurance, pharmacy, laboratory, research-participant, or contraceptive services. It is not submitted as a medical device and does not claim regulatory clearance. No professional healthcare credential is required to use it.

The app does not provide licensed third-party media, a third-party content catalog, or public user-generated content. The app icon, interface copy, general educational copy, and daily supportive messages are app-owned materials. `[FINALIZE BEFORE SENDING: developer must confirm authorship/licensing and sign the accompanying content-rights declaration if Apple requests evidence.]`

Accordingly, there are no medical-service licenses, third-party content licenses, or research-ethics approvals applicable to this app.

## 9. In-App Purchases and purchase locations

Any one of the following products unlocks the same Maren Premium entitlement:

| Product | Type | Product ID | U.S. reference price | What it provides |
|---|---|---|---:|---|
| Maren Premium Monthly | Auto-renewable subscription, 1 month | `cd.cc.vela.premium.monthly` | USD 3.99/month | Ongoing access to all Premium features while the subscription is active |
| Maren Premium Yearly | Auto-renewable subscription, 1 year | `cd.cc.vela.premium.yearly` | USD 29.99/year | Ongoing access to all Premium features while the subscription is active |
| Maren Premium Lifetime | Non-consumable | `cd.cc.vela.premium.lifetime` | USD 69.99 one time | Permanent access to all Premium features |

Premium unlocks:

- On-device personalized insights that update as the user adds records.
- 30-day mood trend, symptom/tracker frequency, and weight trend charts.
- Advanced reminders: multiple medication times, weekday schedules, custom period reminder lead time, PMS self-care reminders, and phase-aware smart reminders.
- All five color themes (the default rose theme is free; Premium unlocks the other four).
- Unlimited custom tracking items (the free tier supports up to three).

Core tracking, basic period estimates, cycle history, period/day logging, basic reminders, the educational PCOS page, data export, data deletion, Apple Health, and app lock remain available without Premium.

Purchase locations:

1. **Trends tab > Upgrade to Unlock** on any locked Premium card.
2. **Settings tab > Maren Premium > Upgrade Maren Premium**.
3. **Settings tab > Pro Advanced Reminders**.
4. Attempting to add more than three custom tracking items in the free tier.

The purchase screen displays the localized StoreKit product name, description, price, and billing period, together with clear subscription disclosure (payment charged to the Apple ID at confirmation, automatic renewal, cancellation at least 24 hours before the period ends, renewal-charge timing, and manage/cancel in App Store settings), Privacy Policy, Terms of Use, and **Restore Purchases**. A second Restore Purchases entry is available at **Settings > Maren Premium > Restore Purchases**. The lifetime product is a one-time payment.

The monthly and yearly products are in the same subscription group and should be assigned the same subscription level so the user cannot hold both variants simultaneously. Premium entitlement is available on the user's devices through the App Store transaction history; no Maren login is required.

## 10. Review links

- Privacy Policy: <https://junyu17.github.io/Maren/privacy.html>
- Terms of Use: <https://junyu17.github.io/Maren/terms.html>
- Support / product website: <https://junyu17.github.io/Maren/>

Please let us know if you need any additional test instructions or documentation. Thank you for reviewing Maren.

Sincerely,  
Jun Yu  
billy.yu@me.com  
`[PHONE NUMBER REQUIRED IN APP REVIEW INFORMATION]`
