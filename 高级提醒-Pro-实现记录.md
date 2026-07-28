# 高级提醒(Pro)实现记录 · 2026-07-28

> Maren(Vela)新增 Premium 功能「高级提醒」。本次改动已 `xcodegen generate` + 模拟器编译通过(`BUILD SUCCEEDED`)并启动验证无崩溃。

## 一、需求(来自 Jun)

Pro 高级提醒 = 更灵活/更聪明的那层:
1. **用药一天多次**(早/中/晚多个时间点)、**按周几不同**
2. **经期提醒自定义提前天数(1–5 天)** + 额外的 **PMS/黄体期「对自己好点」提醒**
3. **按周期阶段的智能提醒**(如「你的焦虑常在黄体期升高--这几天注意休息」)

定价:**$3.99/月 · $29.99/年 · 买断 $69.99**(原 $19.99–24.99/年、$39–49 买断已上调)。

## 二、实现总览

全部走系统本地通知(`UNUserNotificationCenter`),**不联网、无推送服务器**,符合本地优先铁律。Pro 调度入口一律由调用方用 `Store.shared.premium` 把关;免费层强制以 `false`/固定值传入,确保不残留旧排期。

| 功能 | 免费层 | Pro |
|---|---|---|
| 每日记录提醒 | ✅ 固定时刻 | ✅ |
| 经期临近提醒 | ✅ 固定提前 2 天 | ✅ 提前 1–5 天可自定义 |
| PMS/黄体期关怀提醒 | ❌ | ✅ 经期前 N 天(默认 4)一条「对自己好点」 |
| 按周期阶段智能提醒 | ❌ | ✅ 进入黄体期时,按用户记录个性化 |
| 用药提醒 | ✅ 单次每日 | ✅ 多时段 + 按周几 |

## 三、新增 / 修改文件

### 新增
- **`Sources/Support/AdvancedReminders.swift`**
  - `ReminderSlot`(Codable):单个用药时段 = {hour, minute, weekdays[]};`weekdaysLabel` 用系统本地化周几符号。
  - `MedicationSlotsPolicy.maxSlots = 6`(受系统 64 条 pending 通知上限约束:6×7=42 + 其它提醒仍在 64 内)。
  - `ProReminderSettings`:Pro 开关与参数的 UserDefaults 读写(经期提前天数、PMS 开关、智能提醒开关、PMS 提前天数),带范围 clamp。
  - `SmartReminderEngine`:复用 `InsightEngine`/`PhaseModel` 的「症状 × 阶段」思路,只看黄体期。规则:某症状在黄体期出现 ≥3 次且占比 ≥50% → 「你的「X」常在黄体期升高」;否则心情在黄体期明显偏低 → 情绪关怀;都没有 → 通用黄体期关怀。触发点 = 预测下次经期 − 黄体期长度(14,与 `PhaseModel` 口径一致),不写死排卵/安全期,只做趋势关怀话术。

### 修改
- **`Sources/Models/Medication.swift`**
  - 加两个字段(带默认值,SwiftData 轻量迁移):`proScheduleEnabled: Bool`、`scheduleSlotsJSON: String`(存 `[ReminderSlot]` 的 JSON,避免为每个时段建关系表)。
  - 计算属性 `slots`、`setSlots(_:)`(写入时 cap 到 `maxSlots`)。
  - `allReminderNotificationIds()`:确定性的通知 id 全集(单次 + 各下标 × 各周几),供「先全撤再重排」用,不依赖旧 slot id,无竞态。
- **`Sources/Support/NotificationManager.swift`**
  - `schedulePeriodReminder(enabled:nextPeriodStart:)` → 改签名为 `(enabled:advanceDays:nextPeriodStart:)`,正文按实际天数插值。
  - 新增 `schedulePMSReminder(enabled:nextPeriodStart:)`(Pro)。
  - 新增 `scheduleSmartReminders(enabled:prediction:logs:)`(Pro)。
  - 新增 `scheduleMedicationSlots(notificationId:name:slots:)`(Pro 多时段,每个 slot×weekday 一条 repeating 通知)与 `cancelAllMedicationReminders(notificationId:)`(确定性 id 全集撤排,无竞态)。
  - 保留 `scheduleMedicationReminder`/`cancelMedicationReminder`(免费单次,兼容)。
- **`Sources/Views/SettingsView.swift`**
  - 加 Pro 偏好 `@AppStorage`(经期提前天数、PMS、智能提醒)。
  - 经期提醒区:Premium 显示「提前提醒天数」Stepper(1–5);非 Premium footer 提示升级。
  - 新增「Pro · 高级提醒」区:Premium 显示 PMS / 智能提醒开关 + 智能提醒预览(实时算当前数据会显示什么);非 Premium 显示锁定入口跳付费墙。
  - `reschedule()` 同步排 PMS + 智能提醒;`deleteAllData()` 一并清 Pro 排期。
- **`Sources/Views/CalendarView.swift`**
  - `refreshPeriodReminder()`(经期数据变化时)同步重排经期 / PMS / 智能提醒,跟随新预测。
- **`Sources/Views/MedicationManagerView.swift`**(含 `MedicationEditor`)
  - 编辑器:Premium 多一个「高级排程(多时段 / 按周几)」开关;开启后用多时段编辑器(每行:时间 + `WeekdayPicker` 周几选择 + 删除,可加到 6 个);关闭则回退单次。
  - 列表行摘要:Pro 显示「N 个提醒时段」,否则原「每天 HH:mm 提醒」。
  - 保存流程:先 `cancelAllMedicationReminders` 撤旧,再按 Pro/单次重排;删除药用 `cancelAllMedicationReminders`。
  - 新增 `WeekdayPicker`:7 个可切换按钮,用系统 `shortWeekdaySymbols`,带 isSelected 无障碍特征。
- **`Sources/Views/PaywallView.swift`**:featureList 加「高级提醒」卖点行(图标 `bell.badge.fill`)。价格仍由 StoreKit 动态取,不写死。
- **`Resources/Localizable.xcstrings`**:新增 25 条文案(en + zh-Hans),0 删除、0 reformat。Int 插值用 `%lld`、String 用 `%@`,遵循项目约定。
- **`CLAUDE.md`**:更新定价为 $3.99/月 · $29.99/年 · $69.99;内购段补「高级提醒」已解锁说明。
- **`内购配置指南.md`**:价格表更新;功能边界补「高级提醒」。
- **`Vela.xcodeproj`**:`xcodegen generate` 重新生成(纳入新文件)。

## 四、关键设计决策

1. **Medication 加字段而非新建关系表**:多时段存 JSON 单字段,CloudKit 同步简单,SwiftData 轻量迁移即可(app 尚未上架,迁移风险低)。
2. **通知 id 用确定性下标方案**:`vela.med.<uuid>.s<index>[.w<weekday>]`。撤排时按「全集」remove(不存在的 id 被忽略),无需旧 slot id,无 getPending 竞态。
3. **智能提醒只做黄体期**:用户示例就是黄体期;且黄体期起点 = 下次经期 − 14,可稳定计算。数据不足静默不生成(沿用 InsightEngine 的诚实叙事)。
4. **Pro 调度把关在调用方**:`Store.shared.premium` 在 SettingsView/CalendarView/MedicationManagerView 判断后传 `enabled`,免费层传 false,确保升级/降级时旧 Pro 排期被清掉。
5. **经期提前天数**:免费层固定 2(行为不变);Pro 可改 1–5。设置项 UI 仅 Premium 可见。

## 五、构建与验证

- `xcodegen generate` ✅
- `xcodebuild -scheme Vela -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**(主 app + Widget + Watch)。
- 模拟器(iPhone 17)安装 + 启动:进程稳定不崩溃,日志无 error/crash/SwiftData 迁移错误。
- 截图:`/tmp/maren_launch.png`、`/tmp/maren_settings.png`(设置页含 Pro 区)。

## 六、待 Billy 确认 / 后续

1. **App Store Connect 产品定价**:年订阅 $29.99、买断 $69.99(月 $3.99 不变)需在 ASC 改;代码不写死价格。
2. **本地 StoreKit 测试**:项目暂无 `Vela.storekit`;按 `内购配置指南.md` 在 Xcode 建一份(用新价格),Edit Scheme 选它,才能在模拟器看到付费墙产品与测试购买/解锁 Pro。
3. **真机回归**:验证 Medication 加字段的轻量迁移在「有旧数据」的设备上正常(模拟器是全新数据,没测到迁移路径)。
4. **通知权限**:Pro 提醒依赖已授权通知;首次开 Pro 开关时若未授权,需先走「开启通知权限」。
5. **视觉走查**:我无法看图,设置页「Pro · 高级提醒」区、用药编辑器多时段/周几选择器、付费墙新卖点行的视觉请 Billy 过一眼。
6. **可选增强**:PMS 提前天数目前固定 4 天(代码常量,未做 UI);如要可调可加 Stepper。智能提醒目前只排「下次黄体期」一次,周期刷新时会重排;如要覆盖多周期可扩展。
