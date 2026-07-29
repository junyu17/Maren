# Maren — Privacy Policy / 隐私政策

> **Effective date / 生效日期:** [FILL BEFORE LAUNCH]
> **Contact / 联系:** [your-support-email]
>
> ⚠️ **重要提醒(给 Billy,非用户可见)**:我(Claude)不是律师,以下是基于 Maren「本地优先」架构起草的隐私政策 + 自审清单。它写得已经相当扎实且贴合美区 App Store 与 Apple「App Privacy」要求,但**它成立的唯一前提是:app 的实际行为和下面写的一字不差**。Flo 就是政策写得漂亮、代码却把数据发给了 Facebook,被 FTC 罚。所以这份文件既是给用户看的,也是你的**开发验收清单**。落地前请至少走一遍文末 §Self-Audit。

---

## Privacy Policy (English — App Store submission version)

**Your health data is yours. We built Maren so that we never see it.**

> **Scope note - what the current version (v0.1) actually does.** This policy must describe the shipped
> binary exactly. By default the current version stores your **health data** (cycles, symptoms, mood,
> medications) **only on this device** - it never transmits health data anywhere unless you explicitly turn
> on a feature. It includes: **StoreKit (Apple In-App Purchase)** for the optional Maren Premium upgrade
> (purchase transactions handled by Apple; we receive only your entitlement status, never your payment
> details); **optional iCloud (CloudKit) sync** (off by default; when on, data syncs to your own private
> iCloud account - see §3); and **optional Apple Health integration** (see §4). It contains **no analytics
> SDK, and no networking code of any kind other than StoreKit's communication with Apple and, if you enable
> sync, Apple's CloudKit.** Section 5 (Analytics) describes a feature that is **not present in the current
> version** and is marked accordingly - do not publish it as active until the corresponding code actually
> ships.

### 1. The short version
- Your cycle, symptom, and mood entries are stored **on your device** by default. You may optionally turn on **iCloud sync (§3)** to sync them to your own private iCloud account across your devices.
- **We do not operate a server that stores your health data.** We cannot read it.
- **We do not sell, rent, or share your personal or health data with anyone.**
- **We do not use your data for advertising**, and we do not embed third‑party advertising or social‑media tracking SDKs.
- You can **export all your data** (CSV/PDF) or **delete it** at any time.

### 2. What data Maren handles and where it lives
| Data | Where it is stored | Who can access it |
|---|---|---|
| Cycle, period, symptom, mood entries you log | Your device (local storage) by default; your private iCloud if you turn on sync (§3) | **Only you.** Not us. Not third parties. |
| App settings & preferences | Your device / your iCloud | Only you |
| Anonymous, aggregated crash & usage stats | **None collected in v0.1** (see §5) | — |
| Purchase/subscription status | Apple (StoreKit) | Apple and us (status only, no health data) |

We do **not** collect your name, email, phone number, contacts, precise location, or advertising identifier for the purpose of tracking.

### 3. iCloud sync(可选,默认关闭,已实装)
If you enable sync, your data is stored in **your own iCloud account** using Apple's CloudKit private database. It is transmitted and stored under Apple's encryption. **Maren's developer has no access to your CloudKit private data.** Sync is entirely optional; with it off, your data never leaves your device except when you choose to export it.

### 4. Apple Health(可选,已实装)
If you grant permission, Maren may read from and/or write to Apple Health. Data obtained from HealthKit is used **only** to provide in‑app features on your device, is **never** used for advertising or marketing, and is **never** shared with third parties or sold, consistent with Apple's HealthKit requirements.

### 5. Analytics — *NOT USED IN THE CURRENT VERSION*
**The current version collects no analytics at all and contains no analytics SDK.** If this ever changes: to fix crashes and improve the app we may collect **anonymous, aggregated** technical data (e.g., crash logs, feature‑usage counts) via a privacy‑focused analytics provider that does **not** collect personal identifiers and does **not** build user profiles. This data cannot be tied back to you and **never** includes your health entries. You can opt out in Settings. *(Provider to name here, e.g. TelemetryDeck — or remove this section if no analytics.)*

### 6. Purchases
Subscriptions and one‑time purchases are processed by **Apple** via StoreKit. We receive only your entitlement status (whether you have Premium). We never receive your payment details.

### 7. What Maren is NOT
Maren is a **tracking and insight** tool for personal awareness. **It is not a contraceptive, not a medical device, and does not provide medical advice or guarantees about fertility, ovulation, or pregnancy prevention.** Predictions are estimates and may be inaccurate, especially for irregular cycles. Always consult a qualified healthcare professional for medical decisions.

### 8. Children
Maren is not directed to children under 13 (under 16 in the EEA/UK). We do not knowingly collect data from them.

### 9. Your rights & controls
You can, at any time, from within the app: view all your data, export it (CSV/PDF), and permanently delete it. Deleting the app removes local data; if sync was enabled, you can delete iCloud data from within the app or via iOS iCloud settings. Because we do not hold your data on our servers, most data‑subject requests (GDPR/CCPA access, deletion, portability) you can fulfill yourself directly in the app. For questions, contact [your-support-email].

### 10. Legal bases & regions
We process the minimal data described above to provide the service you request. This policy is designed to align with **GDPR (EEA/UK)** and **CCPA/CPRA (California)** principles. Where required, health data is treated as sensitive/special‑category data and is processed only on your device / your iCloud with your consent.

### 11. Changes
We will post any changes here and update the effective date. Material changes will be surfaced in‑app.

### 12. Contact
[Developer / entity name] — [your-support-email] — [optional address]

---

## 中文摘要(可放官网,非 App Store 提交版)

- 你记录的周期、症状、情绪数据**只存在你手机 + 你自己的 iCloud**。
- **我们没有存你健康数据的服务器,我们看不到你的数据。**
- **绝不出售、出租、共享**你的个人/健康数据;**不用于广告**;不嵌入第三方广告/社交追踪 SDK。
- 数据可**随时导出(CSV/PDF)或删除**。
- Maren 是**追踪与洞察工具,不是避孕工具、不是医疗器械**,预测仅为估算(不规律周期尤其可能不准),医疗决定请咨询专业医生。

---

## §Self-Audit — 上线前合规自审清单(给 Billy,务必逐条打钩)

政策要成立,app 必须真的做到以下每一条。**任何一条做不到,就必须改政策文字或改代码,不能骗用户(这是法律红线)。**

- [ ] **没有**把任何健康数据发送到我们自建/租用的服务器。
- [ ] **没有**集成 Facebook SDK、Google Analytics(含 Firebase Analytics)、任何广告 SDK、任何 attribution/追踪 SDK。(Flo 的原罪就在这。)
- [ ] 如接 TelemetryDeck 之类分析:确认它**匿名、不采集设备广告 ID、不含健康数据**;并在 Settings 提供关闭开关。
- [x] iCloud 同步用的是 **CloudKit 私有库(private database,代码用 `.private(containerIdentifier)`)**,不是 public 库。✅
- [ ] HealthKit 数据**仅本地使用**,不外传、不用于营销。
- [ ] app 内提供**导出**和**永久删除**入口,且删除是真删。
- [ ] 文案全局搜索并移除 "birth control"、"safe days"、"contraception"、"guaranteed"、"prevent pregnancy" 等词。
- [ ] app 内显著位置放**医疗免责声明**(§7 内容)。
- [ ] Apple App Store Connect 的 **"App Privacy" 问卷**如实填写(数据类型、是否用于追踪);因为我们不追踪,大部分可勾"Data Not Collected / Not Linked to You"。
- [ ] 隐私政策 URL 上线可访问(放官网,填进 App Store Connect)。
- [ ] 填好本文件里所有 `[FILL...]` / `[your-...]` 占位符。

> 我不是律师,这份文件把风险降到很低但不能替代法律意见。若日后进军欧盟或做付费医疗声明,建议届时再花小钱找律师过一遍——MVP 阶段(本地优先、不做避孕定位、不追踪)按上表执行,风险已可控。
