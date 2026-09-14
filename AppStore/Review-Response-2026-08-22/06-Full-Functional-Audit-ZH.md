# Maren 1.1.0 (8) 全功能审计与审核风险清单

## 审计口径

本报告按当前代码和提审要求列出功能边界，不把历史 build 7 或旧自动化数字当成 build 8 最终证据。当前 build 8 的模拟器自动化、Release 构建、archive、IPA、静态签名与 ASC 上传已有证据；精确 Build 8 实体设备复测与 Apple 录屏仍保持 `PENDING`。

候选：`1.1.0 (8)`

当前实体机门禁：iPhone Air / iOS 26.6.1 和 iPhone 12 / iOS 26.6 需重新安装并确认精确 Build 8。最终 Apple 录屏优先使用 iPhone Air / iOS 26.6.1 或录制当天最新公开系统。
当前 build 8 本地证据：Xcode `26.6 (17F113)`；Vela Review iPhone 17 simulator / iOS `26.5`，397/397 tests passed、0 failures，结果为 `Evidence/Build8/Vela-1.1.0-8-full-tests.xcresult`；Release iOS 与 VelaWatch scheme 构建成功（四个 target）；archive、IPA、SHA-256 和 codesign/App Group 检查记录在提审包 README 中。模拟器证据不替代实体机。
历史开发证据：build 7 及 286/379 测试数字仅作历史背景，不作为 build 8 冻结证据。

## 1. 核心数据与记录

| 功能 | 当前实现边界 | 审核要点 | Build 8 证据 |
|---|---|---|---|
| Today | 每日心情、精力、痛感、睡眠、体重、基础体温、点滴出血、备注、Trackers、用药打卡和 Apple Health 只读数据 | 保存后应立即显示；空记录不应污染历史 | `PENDING` 实体机录屏 |
| Calendar | Calendar 同时用于展示和记录经期/流量 | 必须展示新增、修改、删除后的实时状态 | `PENDING` |
| PeriodDay 删除 | Calendar 与历史页使用统一删除 helper；删除前捕获 dayKey；HealthKit 下一本地经期日的 cycle-start 重新计算 | HealthKit 失败时本机删除结果和同步失败提示要分开 | `PENDING` |
| DailyLog 删除 | 本机持久化删除后刷新 Widget/提醒，再尽力清理 Maren 写入的 HealthKit 样本 | 不得把刷新或 HealthKit 失败误报为本机未删除 | `PENDING` |
| 用户内容历史 | 每日记录、经期、用药打卡、书签/记录和相关本机内容提供左滑删除 | 所有可删除内容使用真实左滑，不展示伪造按钮结果 | `PENDING` |
| Delete All Data | 清理五个本机模型、提醒、手动周期、Widget/Watch 快照、快速记录队列和本机教育书签；仅尽力删除 Maren 写入的 HealthKit 样本 | Apple Health 中其他来源的数据不删除；失败必须显示部分清理提示 | `PENDING` |

## 2. Tracker、用药和实时一致性

| 功能 | 当前实现边界 | 审核要点 | Build 8 证据 |
|---|---|---|---|
| 内置 Trackers | 106 个内置项，分类、搜索、选择和取消选择 | 选择后保存，重新进入仍可见 | `PENDING` |
| 自定义 Tracker 新建 | label + emoji，存入本机 CustomSymptom | 保存失败时编辑器保持打开 | `PENDING` |
| 自定义 Tracker 编辑 | 原地修改 label/emoji，保留稳定 key；历史 DailyLog.symptoms 不迁移、不丢失 | 修改后 Today、历史、趋势显示新名称 | `PENDING` |
| 自定义 Tracker 删除 | 删除定义并从所有历史 DailyLog 中移除对应 key；刷新静态标签快照 | 删除后不存在失效标签或旧名称 | `PENDING` |
| Medication 编辑 | 保存失败时编辑器保持打开；成功后安排本地提醒 | 不把系统通知授权误写成云端服务 | `PENDING` |
| Medication/Intake 删除 | 药物定义与打卡历史可分别从管理/历史入口删除，删除定义会级联清理 intake 并取消提醒 | 左滑删除后列表、提醒和历史同步 | `PENDING` |
| 实时事件 | LocalDataChangeCenter 以 revision 发布 quick log、删除、Tracker 改动等事件；同日脏草稿进入冲突路径 | 同日 Widget/Watch/Shortcut 写入不能静默覆盖用户正在编辑的草稿 | `PENDING` |
| 全局本地搜索 | Calendar、Today、Trends、Library、Settings 共用本地索引；覆盖教育文章、内置/自定义 Tracker、药物、DailyLog 和 PeriodDay；支持多词、前缀/子串和容错排序 | 结果去重且排序稳定；点按进入准确文章、控件、编辑页或日期；SwiftData 新增/修改/删除后实时重算，不上传查询或记录 | 43 个搜索专项测试通过；build-8 全量 397/397；实体录屏 `PENDING` |

## 3. Quick actions、Widget、Watch

- Widget/App Shortcut 队列采用 `peek → applyWithKeys → acknowledge`，只有 SwiftData 保存成功才确认有效条目。
- 无效或 replay-blocked 条目可被安全丢弃；有效条目保存失败时仍留在队列。
- 成功后刷新 SwiftData 派生数据、Widget 时间线和本地提醒，发布 `.quickLogApplied`，并对受影响 dayKey 做 HealthKit best-effort 同步。
- PhoneConnectivity 的 sendMessage、transferUserInfo 和 applicationContext 都进入同一落库路径。
- Watch 只交换用户主动快速记录和本地摘要，不建立开发者服务器。
- 录屏必须展示至少一条实际 quick log 从 Widget/Shortcut/Watch 到 iPhone 的实时结果；无法配对时不能用模拟器日志代替。

Build 8 实体设备证据：`PENDING`。

## 4. Perimenopause、Stories 与教育

### 免费 Perimenopause record summary

用户在 Settings 主动选择 Perimenopause 记录上下文后，Trends 中显示 30 天和 90 天的描述性记录摘要，包括覆盖、周期范围、可用平均值、症状/情绪/睡眠记录事实等。它不自动判断用户是否处于围绝经期，不给诊断、治疗、预测或医疗建议，也不因为 Premium 状态而隐藏基本摘要。

### Premium advanced insights

Premium 另行解锁高级趋势、情绪/Tracker 频次、周期对比、相关性探索、高级提醒、自定义报告范围/备注、额外强调色主题和无限自定义 Tracker。付费墙必须明确 Premium 是洞察/高级功能层，而不是解锁用户已经产生的基础健康记录。

### Daily Stories / personalized education cards

Daily Story 和个性化教育卡片从本地教育资源与用户已记录的上下文选择，不要求账号或网络内容服务。文章、故事、引用和支持性文案均为原创、委托制作或合法授权内容。

Build 8 实体 UI/内容证据：`PENDING`。

## 5. HealthKit、通知与隐私

当前七个可选 HealthKit 类型：

1. 经期流量：可读写（用户选择并授权后）；
2. 体重：可读写；
3. 睡眠分析：只读导入；
4. 基础体温：可读写；
5. 点滴出血：可读写；
6. 步数：只读导入；
7. Apple 锻炼时间：只读导入。

权限只从 Settings > Apple Health 的用户操作触发。Maren 不请求位置、通讯录、相机、麦克风、照片、Bluetooth、Motion & Fitness、广告标识符或 App Tracking Transparency。通知是本地提醒；Face ID/Touch ID/设备密码只用于本机 App Lock。

审计风险：真实实体机上 HealthKit 的授权结果取决于设备、系统和用户现有权限。录屏、App Privacy、Info.plist usage description 和隐私网页必须保持同一读写边界；不得把模拟器的 entitlement 警告写成 App 功能失败，也不得把未实际弹出的授权写成已授权。

Build 8 实体权限证据：`PENDING`。

## 6. IAP 与 Premium 语义

| 产品 | ID | Apple 类型 | 文案边界 |
|---|---|---|---|
| Monthly | `cd.cc.vela.premium.monthly` | Auto-renewable，1 month | 每月自动续费；当前配置无试用；价格由 StoreKit 提供 |
| Yearly | `cd.cc.vela.premium.yearly` | Auto-renewable，1 year | 符合 Apple 资格时显示 7 天 introductory free trial，之后按年自动续费；价格由 StoreKit 提供 |
| Lifetime | `cd.cc.vela.premium.lifetime` | Non-consumable | 一次性购买、永久有效、无自动续费 |

入口：Trends 的单一 Maren Premium 卡片、Settings > Maren Premium、Settings > Pro Advanced Reminders、免费 custom Tracker 上限。付费墙必须显示 Restore Purchases、隐私政策、使用条款、管理订阅和自动续费说明。

风险控制：不能在月订阅上写 7 天试用；不能对不符合 Apple 资格的年订阅用户强行承诺试用；不能把终身购买说成订阅；不能用 UserDefaults 代替已验签 StoreKit entitlement。

Sandbox/TestFlight 实际购买、恢复、pending、取消、过期和试用证据：`PENDING`。

## 7. 外部服务、地区和监管

- 无开发者后端、CloudKit/iCloud 健康数据同步、第三方登录、分析、广告、AI、社交网络或第三方支付处理器。
- 使用 Apple SwiftData、StoreKit 2、HealthKit、UserNotifications、LocalAuthentication、App Intents/Shortcuts、WidgetKit/App Groups、WatchConnectivity 和 Files。
- 核心功能和内容行为跨地区一致；英文/简体中文由系统语言选择。
- Apple StoreKit 价格、币种、税、产品可售地区和 introductory-offer eligibility 可能因 storefront 变化；系统权限文案和 HealthKit 可用性也由设备/地区/系统决定。
- 不提供医疗、远程医疗、药房、实验室、保险、临床、避孕或生育服务；不是医疗器械。

## 8. 审核提交前的证据缺口

1. 使用 iPhone Air / iOS 26.6.1（或录制当天最新公开系统）完成一镜到底录屏并上传。
2. 实体 HealthKit、通知、Face ID、Widget、Shortcut、Watch 和动态字体结果。
3. Sandbox/TestFlight 三个 IAP、年订阅七天试用、恢复和自动续费验证。
Build 8 ASC 上传已成功；Processing/选择、精确 Build 8 两台实体测试与录屏尚待闭环。五项 Draft Submission、App Privacy、年龄分级、IAP metadata、review screenshot、年度试用和 Review Notes 第 2–8 点已完成并保存；App 不属于受监管临床服务且不包含受保护第三方媒体目录，无需额外资质；最终 `Submit for Review` 未点击。

最终录屏上传前，`05-Test-Matrix.csv` 中对应的录屏和提交行保持 `PENDING`；build-8 本地测试/构建/archive/IPA/签名行已完成并有证据，ASC Processing/选择与两台实体设备复测待完成。
