# ⛵ Maren

**Your cycle, your mood, your data.**

Maren is a privacy-first period, mood & symptom tracker for iPhone. Your health data stays on your device — we never see it, sell it, or lock it behind a paywall. Built for real cycles, including irregular and PCOS cycles (15–120 days).

🌐 **Website:** https://junyu17.github.io/Maren/ · 🔒 **Privacy:** https://junyu17.github.io/Maren/privacy.html · 📄 **Terms:** https://junyu17.github.io/Maren/terms.html

---

## Why Maren

Most period apps trap your history behind subscriptions, get caught selling data, or predict poorly for irregular cycles. Maren is the opposite:

- **Local-first.** Entries live on your device. Optional iCloud sync uses *your own* private iCloud — even we can't access it.
- **No selling, no ads, no trackers.** No third-party advertising or tracking SDKs. Ever.
- **Free forever for tracking.** Logging, basic prediction, daily quotes, and data export (CSV/PDF) are always free.
- **Honest prediction.** Learns *your* cycle (no "day 14" assumption); shows a confidence range instead of fake precision. Supports 15–120 day cycles.
- **Not a contraceptive.** A tracking & insight tool — not a medical device, no fertility/ovulation guarantees.

## Features

- Cycle calendar with four color-coded phases + adaptive prediction
- 3-second daily mood / symptom / sleep / weight check-in (custom symptoms too)
- On-device personal insights (Premium)
- Smart reminders: period, PMS self-care, phase-aware; medication multi-time & weekday scheduling (Premium)
- Optional Apple Health two-way sync · optional iCloud sync · Apple Watch quick-log · home-screen widgets
- Face ID lock · themes · full data export & delete

## Pricing

| Tier | Price |
|---|---|
| Free | $0 forever — all tracking, basic prediction, daily quote, export, Face ID, Apple Health, iCloud sync |
| Premium Monthly | $3.99 / month |
| Premium Yearly | $29.99 / year (best value) |
| Premium Lifetime | $69.99 one-time, forever |

In-app products: `cd.cc.vela.premium.yearly` / `.monthly` / `.lifetime` (StoreKit 2).

## Tech stack

Swift · SwiftUI · SwiftData · CloudKit (private DB, optional) · HealthKit · StoreKit 2 · WidgetKit · WatchConnectivity. iOS 17+. Project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

## Build

```bash
xcodegen generate
open Vela.xcodeproj
# then build/run the `Vela` scheme in Xcode (iOS 17+ simulator)
```

Signing: set your development team in `project.yml` (`DEVELOPMENT_TEAM`) or Xcode Signing & Capabilities.

## Repository layout

```
Sources/        iOS app (models, support, views)
WatchSources/   watchOS app
WidgetSources/  home-screen widgets
Shared/         shared types (WidgetSnapshot, QuickLog)
Resources/      localizations, quotes, assets
AppStore/       App Store submission docs (privacy policy, terms, listing checklist)
docs/           GitHub Pages site (website + privacy + terms)
project.yml     XcodeGen project definition (single source of truth)
```

## Disclaimer

Maren is a tracking and insight tool for personal awareness. It is **not a contraceptive, not a medical device**, and does not provide medical advice or guarantees about fertility, ovulation, or pregnancy prevention. Always consult a qualified healthcare professional for medical decisions.

## Contact

Jun Yu — billy.yu@me.com
