# Vela — 项目开发上下文(CLAUDE.md)

> 这是 Vela app 的开发上下文。新对话在本目录打开时会自动加载本文件。
> 完整立项依据见同目录 `Vela-项目立项书.md`;隐私政策见 `docs/privacy.html`(App Store 版为 `AppStore/privacy-policy.md`)。

## 这是什么

**Vela** = 一款 **iOS 隐私优先的女性健康 & 情绪追踪 app**。
定位口号:**"你的数据永远属于你。"**
差异化楔子(全部来自真实竞品差评,已核查):正面攻击 Flo/Clue/Natural Cycles 的三大痛点 —— **订阅陷阱、隐私滥用、对不规律/PCOS 周期预测不准**。

## 铁律(开发中不可违反)

1. **本地优先(local-first)**:健康数据只存**用户设备本地(SwiftData 本地库)**,**不进入 iCloud/CloudKit**。我们的服务器**永不接触**用户健康数据。这既是卖点,也是隐私政策成立的前提。
2. **用户录入的数据永久免费、可导出**,绝不锁进付费墙。
3. **绝不定位成避孕/安全期/排卵保证工具** —— 文案只用「追踪 + 趋势洞察」,规避医疗责任。避免出现 "safe days"、"birth control"、"guaranteed"、"prevent pregnancy" 等词。
   - ✅ **已拍板,勿再提问(2026-07-23 Billy 决定)**:日历**展示完整四阶段(经期/卵泡期/排卵期/黄体期)并多色标注是允许的**,已实装。红线是**定位与话术**,不是阶段展示本身。详见立项书 §3.4。
   - 配套硬性要求(改动时不得移除):① 阶段图例下方必须有免责声明(统计预测/仅供参考/不构成医学建议/不可作为避孕或备孕依据);② 排卵日必须用「下次经期倒推黄体期」估算,不得写死「第 14 天」。
4. **零第三方数据共享、不用于广告** —— 隐私政策怎么写,代码就必须怎么做(Flo 就是嘴上说一套做一套被 FTC 罚的)。

## 技术栈

- Swift + SwiftUI,iOS 17+
- 本地存储:SwiftData(**仅本机,不接 CloudKit/iCloud**)
- 同步:无跨设备同步(2026-08-14 已移除 CloudKit 选项 —— App Review Guideline 5.1.3(ii) 禁止把个人健康信息存入 iCloud)
- 健康数据:HealthKit(可选授权)
- 预测:设备端自适应统计模型 —— **不写死「第 14 天排卵」**,学用户真实周期,支持 15–120 天长/不规律周期(PCOS 友好),呈现置信区间而非假装精准
- 每日一句:本地 JSON 词库 + 按周期阶段匹配
- 图表:Swift Charts
- 通知:UserNotifications
- 内购:StoreKit 2(已实装,见下)
- 分析:TelemetryDeck(匿名)或不接

### 内购(已实装,2026-07-27)

- 代码:`Sources/Support/Store.swift`(`Store.shared`,StoreKit 2)+ `Sources/Views/PaywallView.swift`。
- 产品 ID:`cd.cc.vela.premium.yearly` / `.monthly` / `.lifetime`(写死在 `Store.ProductID`,改 ID 要同步改)。
- entitlement 存本机 UserDefaults(`store.premium`),启动与交易更新时用 `Transaction.currentEntitlements` 校验。
- 首批解锁功能:「趋势·洞察」卡(`InsightEngine`)。要锁更多功能就加 `if Store.shared.premium { … } else { /* 锁定态 */ }`。
- 已解锁功能:「趋势·洞察」(`InsightEngine`)+ **「高级提醒」(Pro)**:经期提前天数自定义(1–5)、PMS/黄体期关怀提醒、按周期阶段的智能提醒(`SmartReminderEngine`)、用药多时段 + 按周几排程(`ReminderSlot`)。Pro 入口在设置页「Pro · 高级提醒」与用药编辑器。
- 未做 App Store Connect 注册前,本地测试需在 Xcode 建 `Vela.storekit` + Edit Scheme 选它;步骤见 `内购配置指南.md`。
- 隐私铁律:购买由 Apple 处理,不接触支付信息、不接触健康数据;必须保留「恢复购买」入口。

## MVP 功能(F1–F8)

- F1 经期/周期日历追踪
- F2 自适应预测引擎(不规律/PCOS 友好)
- F3 情绪+症状每日记录(3 秒打卡,极简、不卡)
- F4 每日激励一句话(按周期阶段智能匹配,离线)
- F5 数据永久免费 + 一键导出(CSV/PDF)
- F6 隐私优先架构(纯本地,服务器零接触)
- F7 趋势图表
- F8 提醒通知

扩展功能:Apple Health 双向同步、Face ID 锁、Apple Watch 与 PCOS 科普保持免费;Premium 付费解锁设备端个性化洞察、深度趋势、高级提醒、额外主题和无限自定义追踪项。

> 实现现状更新(2026-08-14):上表所列 V2 项多已实装(Apple Health 双向同步、Face ID 锁、主题、PCOS 信息页均已上线,高级提醒为 Pro 付费);CloudKit 多设备同步**已按 App Review 5.1.3(ii) 移除**(个人健康信息不得入 iCloud),健康数据纯本地,无跨设备同步。付费墙当前只锁「洞察」「高级提醒」「高级图表」等 Pro 功能。产品决策以此处与《高级提醒-Pro-实现记录.md》为准。

## 定价

Freemium。免费永久含:全部追踪、基础预测、每日一句、数据导出。
Premium:$3.99/月 · $29.99/年 · 终身买断 $69.99。刻意比 Flo($10/月)便宜且提供买断。取消零障碍、无暗黑续费。

## 成本基线

上线 MVP ~$99–200(Apple Developer $99/年是主要开销)。后端≈$0(本地优先,无 CloudKit)。

## 命名与标识(已定型,2026-07-27)

- **品牌名 = Maren**(旧代号 Vela 已弃用为商店名;Vela 在 App Store 被占)。含义「属于海的」,帆船图标沿用。
- **App Store Connect 列表标题 = `Maren: Period & Mood`**(该字段要求全局唯一,故用「品牌+描述」;这是 App Store Connect 手填项,不在代码里)。手机图标下显示名 `CFBundleDisplayName = Maren`(无需唯一)。
- **Bundle IDs**:主 app `cd.cc.vela`、Widget `cd.cc.vela.widget`、Watch `cd.cc.vela.watchkitapp`;App Group `group.cd.cc.vela`。
- **内部标识符仍叫 Vela**(Xcode target/scheme/工程名、Swift 类型如 `VelaApp`/`VelaWidget`、源文件名)——只是代号,不面向用户,勿为改名而大改(会牵连证书/scheme/命令)。构建仍用 `-scheme Vela`。
- ⚠️ **App Store 名称是否可用只有 App Store Connect 的 Name 输入框权威**,网页搜索查不到已预留/未上架的名字——别再用搜索"确认"可用性。

## 关键实现约定(已定型,勿回退)

- **日期主键用整数 `dayKey`(yyyymmdd),不是 `Date`**。`PeriodDay` / `DailyLog` 的唯一键是 `dayKey`;
  `date` 是派生只读属性。原因:`Date` 主键存的是「本地零点」的时间戳,用户跨时区/夏令时后同一天会
  算出不同时间戳,导致重复记录或记录消失。`@Query` 排序请用 `\.dayKey`,不要用 `\.date`;
  `#Predicate` 里也只能用 `dayKey`(`date` 是计算属性,不可入谓词)。
- **本地化**:base 是中文字面量当 key,`Resources/Localizable.xcstrings` 提供 en + 显式 zh-Hans;
  `developmentLanguage: en`,这样未翻译语言回退英文而不是中文。新增用户可见文案必须同时补 en。
- **工程用 XcodeGen 生成**:改 `project.yml` 后跑 `xcodegen generate`;新增/删除源文件也要重新生成。
- **预测计算有界**:`CyclePredictor` 只回溯最近 `lookbackDays`(730 天)的记录,单次重算成本不随使用年限增长。日历页每次刷新只算一次预测再传给子视图,别退回「每个日历格各算一次」。
- **图表轴标签必须本地化**:Swift Charts 的 `.value("…")` 首参用 `String(localized:)`,不要写英文字面量(会被 VoiceOver 朗读、也进数值提示)。
- **本地化插值键必须用「非位置符」**:`String(localized: "你在\(a)最常记录\(b)")` 运行时查表的 key 是**非位置符** `%@`(不是 `%1$@`)。字符串目录里 key 必须写成非位置符才命中,否则英文机上会**回退成中文**;而**值**可以用 `%1$@ %2$@` 做英文语序重排。多参数插值改完务必真的切英文跑一遍确认,别只看 build 通过(缺 key 不报错,静默回退)。

## 开发约定(与 Billy 的协作习惯)

- 改完代码**读回自查一遍**再交付;每次列出**需要在 Xcode 里重新编译/操作的文件清单**。
- 决策类问题给**至少 2 个选项** + 推荐。
- 用 iOS Simulator 工具跑起来自测,别让 Billy 自己去点。

## 建议的开发起点(新对话第一步)

先搭 Xcode 项目骨架 + F1/F3 的 SwiftData 数据模型和基础记录 UI,跑起来能记录、能看日历,再做 F2 预测引擎。
