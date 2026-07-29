# Maren — App Store Connect 上架填写清单

> 一份「照着抄」的清单。带 `代码值` 的必须一字不差(和 app 里写死的对上),否则内购/签名会失败。
> 主打市场美区,主语言 English (U.S.)。

---

## 0. 前置(Developer 门户,一次性)

1. developer.apple.com → Certificates, IDs & Profiles → Identifiers → **注册 App ID**
   - Bundle ID(Explicit):`cd.cc.vela`
   - Capabilities 勾:**App Groups**(`group.cd.cc.vela`)。iCloud/HealthKit 暂不勾(还没启用)。
   - Widget / Watch 的 App ID(`cd.cc.vela.widget` / `cd.cc.vela.watchkitapp`)Xcode 首次带 Team 构建时会自动登记,或手动加。
2. Xcode 里:每个 target → Signing & Capabilities → **Team 选你的账号**,Automatically manage signing 打勾。

---

## 1. 新建 App(My Apps → ＋ → New App)

| 字段 | 填 |
|---|---|
| Platforms | iOS |
| Name | `Maren: Period & Mood` |
| Primary Language | English (U.S.) |
| Bundle ID | `cd.cc.vela` |
| SKU | `maren-ios-001`(自定义唯一串,不对外) |
| User Access | Full Access |

---

## 2. App Information(左栏 General → App Information)

| 字段 | 填 |
|---|---|
| Subtitle(≤30 字符) | `Private period & mood tracker` |
| Category — Primary | Health & Fitness |
| Category — Secondary | Medical(或留空) |
| Content Rights | 勾「Does not contain, show, or access third-party content」 |
| Age Rating | 见文末 §7 问卷 → 结果大概率 **12+** |

---

## 3. 隐私(App Privacy)

- **Privacy Policy URL**(必填):把仓库里 `隐私政策_Privacy-Policy.md` 的英文部分放到一个可访问网页(GitHub Pages / Vercel 免费),粘 URL。
- **Data Collection 问卷**:选 **「No, we do not collect data from this app」**。
  - 依据:健康数据只在本机、无网络层、无分析 SDK、无第三方。内购由 Apple 处理、app 不采集。
  - 这是我们最大的差异化,如实勾「Data Not Collected」即可,别多勾。

---

## 4. 定价(Pricing and Availability)

| 字段 | 填 |
|---|---|
| Price(App 本体) | **Free**(免费下载,靠内购) |
| Availability | All Countries or Regions(或先只开 United States,你定) |

---

## 5. 内购(In-App Purchases / Subscriptions)—— 三个产品,ID 必须一字不差

### 5a. 订阅组(先建一个 Subscription Group)
- Reference Name:`Maren Premium`
- Localization(组显示名):
  - English:`Maren Premium`
  - 简体中文:`Maren 高级版`

### 5b. 年订阅(Auto-Renewable Subscription)
| 字段 | 填 |
|---|---|
| Reference Name | `Maren Premium Yearly` |
| Product ID | `cd.cc.vela.premium.yearly` |
| Subscription Duration | 1 Year |
| Price | **USD 29.99** |
| Display Name (EN) | `Yearly` |
| Description (EN) | `Maren Premium, billed yearly. Best value.` |
| Display Name (ZH) | `按年` |
| Description (ZH) | `Maren 高级版,按年计费,最划算。` |

### 5c. 月订阅(Auto-Renewable Subscription,同一个订阅组)
| 字段 | 填 |
|---|---|
| Reference Name | `Maren Premium Monthly` |
| Product ID | `cd.cc.vela.premium.monthly` |
| Subscription Duration | 1 Month |
| Price | **USD 3.99** |
| Display Name (EN) | `Monthly` |
| Description (EN) | `Maren Premium, billed monthly.` |
| Display Name (ZH) | `按月` |
| Description (ZH) | `Maren 高级版,按月计费。` |

### 5d. 买断 / 终身(**Non-Consumable**,不是订阅!)
> 「买断」在 ASC 里的类型是 **Non-Consumable**,单独建,不在订阅组里。
| 字段 | 填 |
|---|---|
| Type | **Non-Consumable** |
| Reference Name | `Maren Premium Lifetime` |
| Product ID | `cd.cc.vela.premium.lifetime` |
| Price | **USD 69.99** |
| Display Name (EN) | `Lifetime` |
| Description (EN) | `Maren Premium forever. One-time payment.` |
| Display Name (ZH) | `终身` |
| Description (ZH) | `一次买断,永久解锁 Maren 高级版。` |

### 5e. 每个内购都要的两样(首次提交必需)
- **Review Screenshot**:用 `AppStore/screenshots/` 里的付费墙截图(付费墙那张)。三个内购可复用同一张。
- **Review Notes**:`All Premium features unlock together via any one product (yearly/monthly/lifetime). Purchases restore via "Restore Purchases". No login required.`

---

## 6. 版本页(iOS App → 1.0 版本)

**Promotional Text(≤170,可随时改)**
```
Your data stays on your device. Built for irregular & PCOS cycles. No subscription trap — logging and export are free forever.
```

**Description(≤4000)** — 见下方「§Description 全文」,直接复制。

**Keywords(≤100,逗号分隔,不加空格)**
```
period tracker,cycle,menstrual,PCOS,ovulation,mood,symptom,privacy,irregular,calendar,pms,fertility
```

**Support URL**(必填):一个能联系到你的页面(可以是带邮箱的简单网页)。
**Marketing URL**(选填):落地页。

**Screenshots**
- iPhone 6.9"/6.5":上传 `AppStore/screenshots/iphone_1284x2778/` 里的 1–5(日历→趋势→今天→隐私→阶段)。
- Apple Watch:上传 `AppStore/screenshots/watch_410x502/1_watch_glance.png`。

**App Review Information**
- Sign-in required:**No**(app 无账号)
- Contact:你的名字 / 电话 / 邮箱
- Notes:`No account needed; all data is stored locally on-device. HealthKit/CloudKit are not enabled in this build. Insights appear after logging a couple of cycles.`

**Version Release**:Manually release / Automatically 都行。

---

## §Description 全文(复制)

```
Maren is a privacy-first period, mood, and symptom tracker — built for cycles that don't run like clockwork.

YOUR DATA IS ALWAYS YOURS
Your health data lives only on your device. We have no server that stores it, we can't see it, and we never share it with third parties or use it for ads. Export everything or delete it all, anytime — free, forever.

BUILT FOR IRREGULAR & PCOS CYCLES
Maren learns from your real cycles instead of assuming a textbook "day 14." It supports long and irregular cycles (15–120 days) and shows an honest range instead of pretending to be precise.

TRACK IN SECONDS
Log your period and flow, plus mood, energy, pain, sleep, weight, and symptoms in a few taps. A gentle daily note greets you, matched to your cycle phase.

SEE YOUR PATTERNS
A colorful calendar shows your four cycle phases at a glance, with plain-language explanations. Trends show your cycle history and length over time.

MAREN PREMIUM (optional)
Go deeper with on-device personalized insights (mood–cycle links, most frequent symptoms, cycle regularity), advanced reminders (multi-time medication, custom period lead days, PMS self-care, smart phase-based reminders), mood/symptom/weight trend analysis, PCOS-focused support, 5 themes, and unlimited custom trackers. Your logging and data export always stay free.

• Monthly $3.99, Yearly $29.99, or Lifetime $69.99 (one-time)
• Payment is charged to your Apple ID. Subscriptions auto-renew unless turned off at least 24 hours before the period ends; manage or cancel anytime in your App Store settings. Lifetime is a one-time purchase.

Maren is a tracking and insight tool. It is not a contraceptive and does not provide medical advice; predictions are estimates and may be inaccurate, especially for irregular cycles.
```

---

## 7. Age Rating 问卷 关键答法
- Medical/Treatment Information:**None**(我们只做追踪,不给医疗建议/诊断)
- 其余(暴力/性/赌博等):全 None
- → 结果大概率 12+(如问「Unrestricted Web Access」选 No)。

## 8. 提交前最后自查
- [ ] 三个内购 Product ID 与代码 `Store.ProductID` **完全一致**(yearly/monthly/lifetime)。
- [ ] 隐私政策 URL 可访问、内容与 app 行为一致(尤其「不采集/不共享」)。
- [ ] 截图为 1284×2778(iPhone)/ 410×502(Watch)。
- [ ] ⚠️ **HealthKit 未启用**:若这次不上 HealthKit,建议先删掉 project.yml 里
      `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` 两行(避免审核追问"用了 HealthKit 没")。等真启用再加回。
- [ ] 出口合规:已在 Info.plist 设 `ITSAppUsesNonExemptEncryption=NO`,提交时该问卷会自动过。
```
