# Maren 1.1 全功能遍历与审核风险审计

审计目标：即将提审的 `1.1.0 (5)` candidate
代码审计日期：2026-08-21
状态说明：`代码已审计` 只表示源代码/测试路径已检查；实体机、系统授权、真实 StoreKit 购买、签名上传和 App Store Connect 状态仍以证据矩阵为准。

## 1. 启动、导航、隐私和账号边界

- 四页首次引导可跳过，也可进入隔离 Sample Experience。
- 主导航为 Calendar、Today、Trends、Settings；Widget URL 只进入受限的 Calendar/Today 路径。
- 可选 Face ID/Touch ID/设备密码 App Lock；后台或 inactive 后重新锁定，切换器快照使用 privacy-sensitive 标记。
- 本地 SwiftData 打开失败时使用内存降级并提示本次无法持久保存，不把错误伪装成成功保存。
- 无 Maren 账号、注册、登录、邮箱/电话凭据、公共个人资料、社区、私信、公开动态或公共 UGC；私有备注、药物名和自定义 Tracker 只属于本机用户。

审核状态：代码路径已审计；实体解锁、无障碍和小屏布局需在升级后的 iPhone 12 上录像。

## 2. Today、106 项 Tracker 与每日记录

- `TrackerCatalog` 有 106 个内置 Tracker，分为 10 类；Today 的 Tracker picker 支持按显示标签或 key 搜索、折叠分类、选中项移除和自定义项入口。
- Today 可记录心情、能量、疼痛、睡眠、体重、基础体温、点滴出血、症状/自定义 Tracker、私有备注、用药及每日打卡。
- 空白草稿不会生成模型；修改、清空和保存按日期处理，Health 导入来源字段用于避免覆盖用户手工值。
- 免费自定义 Tracker 数量受现有限制，Premium 取消该数量限制；自定义内容不会被发布为 UGC。

审核状态：代码和现有测试路径已审计；106 项搜索、Dynamic Type、VoiceOver 和真实保存流程需实体录像。

## 3. Today Status（设备端观察）

- `TodayStatusEngine` 是 Foundation 纯函数，输入当天心情、能量、疼痛、睡眠、步数、锻炼分钟、Tracker、估算阶段和主动选择的围绝经期模式。
- UI 显示“设备端生成”的最多三条观察；无数据时显示数据不足，而不是补造结论。
- 文案只描述已输入的数值/记录，例如 mood、sleep、steps、exercise 或“logged trackers”；不推断激素、疾病、排卵、受孕或避孕效果。

审核状态：代码/纯引擎测试已审计；不得把 Today Status 写成诊断、预测或医疗建议。

## 4. 排卵/妊娠测试与生殖记录

- Today 的 `ReproductiveTestSection` 只变更当天 Tracker key 集合，并保持其他 Tracker 不变。
- 排卵测试选项为 None、Negative、Positive、Peak；Manual ovulation 是独立开关。
- 妊娠测试选项为 None、Negative、Positive、Invalid。
- UI footer 明确：只记录结果，不解释、不预测、不诊断，也不提供 contraception guidance；代码没有把这些选择送入周期预测或健康结论。

审核状态：`ReproductiveLog` 的互斥、清除、独立开关和无关 key 保留已有测试；实体机需确认页面可达、英文/简中显示和 44pt 触控目标。

## 5. 本地避孕记录与药丸提醒

- Settings > 追踪与提醒 > 避孕记录打开本地 `ContraceptionSettings` 表单；资料仅存 UserDefaults Data，不使用 SwiftData，也不上传。
- 方法包括未记录、pill、ring、patch、injection、IUD、implant、condom、fertility awareness 和 other；可选开始日期、备注和更新日期随本机记录保存。
- 只有 pill 方法显示 daily reminder/time；其他方法自动关闭该开关。保存回调由 Settings 层决定是否请求现有通知授权和排程；组件本身不请求权限。
- 所有文案明确不提供 effectiveness、missed-dose、诊断或医疗建议；该记录不用于安全期、排卵或避孕保证。

审核状态：本地 Codable、suite 隔离、损坏 fallback、clamp/reset、方法支持和 UI 保存路径已有代码/测试；实体通知授权和实际提醒仍需证据。

## 6. 日历、周期估算和阶段教育

- Calendar 支持经期首日、修改/清除和 spotting/light/medium/heavy 流量记录；周期估算基于用户自己的历史，支持现有 15–120 天有效区间并展示范围/覆盖度。
- 阶段信息是从记录得到的估算；界面明确非医疗建议、非精确排卵判断、非避孕/备孕依据。
- Life stage 是用户主动选择的 preference：在 **Settings > Tracking context > Perimenopause** 中选择 Perimenopause（或保留 Cycle tracking）；代码不从症状自动诊断模式。
- 经期变更后刷新 Widget/Watch snapshot 和本地提醒，但不发送到开发者服务器。

审核状态：既有周期/阶段代码和回归测试保留；录屏需展示免责声明和空数据/历史不足提示。

## 7. 围绝经期模式和 30/90 日记录趋势

- 只有用户在 **Settings > Tracking context > Perimenopause** 主动选择 Perimenopause 后，Trends 才显示 Perimenopause summary；未选择时不显示该卡片，也不会自动替用户选择。
- `PerimenopauseTrendEngine` 使用纯 Foundation，提供最近 30 日和最近 90 日及等长前一窗口。
- 输出为 coverage、已记录的症状日、周期长度事实、心情/睡眠平均值、方向/数据不足等描述性统计；样本不足时不显示伪精确平均。
- 30/90 日记录摘要当前为免费功能；Premium 通过独立汇总卡提供高级洞察、心情走势、追踪项频次、周期对比与相关性探索。录屏需分别展示免费摘要和购买/Restore Purchases 入口。
- 同日记录合并、未来日期排除、Calendar/DST 边界、30/90 窗口和方向阈值由引擎测试覆盖；不输出诊断、疾病风险、治疗或因果结论。

审核状态：引擎和定向测试通过；必须在录屏中说清楚这是“记录事实/观察性统计”，不是诊断。

## 8. 知识库、Daily Story 和个性化教育卡

- `EducationCatalog` 从本地 bundle 加载并校验 12 篇双语文章，支持类别、Tracker、阶段和受众标签，文章包含来源、reviewed date 和 non-medical advice。
- **Settings > Library** 支持搜索、分类筛选、打开文章和本地收藏；无远程内容服务。
- Today 的 Daily Story 根据日期、用户已记录 Tracker、估算阶段、主动选择的围绝经期模式和最近已显示文章确定性选择教育卡，并保留短期历史避免重复。
- Daily Story/知识库只是一般性教育内容；不构成诊断、治疗、排卵预测或避孕指导。

审核状态：代码和本地 JSON 校验已审计；最终 candidate 需检查英文/简中文章、来源链接、字体和离线加载失败提示。

## 9. Apple Health 七类选择与只读边界

- Settings > Apple Health 让用户逐类选择：menstrual flow、body mass、sleep analysis、basal body temperature、intermenstrual bleeding、step count、Apple exercise time。
- 授权请求只在用户主动点击连接后发生，并按所选集合建立 read/share 集合。
- Menstrual flow、body mass、basal body temperature、intermenstrual bleeding 可按用户选择读写；sleep analysis、step count、Apple exercise time 明确只读导入。
- 步数和 Apple 锻炼时间导入到 DailyLog 的 `steps` / `exerciseMinutes`，并写入 HealthImportedFields 来源标记；手工值优先。
- 导入过滤 Maren 自己写入的样本，关闭自动同步不伪装成撤销系统权限；Delete All Data 只尝试清理本 App 有权限识别的写入样本。
- Health 数据只在设备和 Apple Health 之间流动，不发送到 Maren 开发者服务器，不用于广告/分析。

审核状态：代码、纯 planner 和回归测试已审计；实体 HealthKit 授权、读取、只读字段显示和撤权边界必须录像/截图。

## 10. 导出、报告、加密备份和删除

- 原始 CSV/PDF 覆盖经期、DailyLog、用药/打卡、自定义 Tracker、Health 来源和本地避孕设置；生成前均提示文件不加密。
- 临床 PDF 采用固定免费范围/内容，Premium 可自定义范围和可选备注；文案保持记录摘要，不宣称临床诊断。
- `.marenbackup` 使用随机 salt/nonce、PBKDF2-HMAC-SHA256、AES-GCM 和认证头；密码至少 8 位，不保存、不日志、不上传且不可恢复。
- 导入先做大小、格式/schema、日期/数值/字符串、唯一 key 和用药引用校验；默认 Merge，Replace 需要破坏性二次确认。
- 模型写入成功后才应用白名单偏好；不恢复 Premium entitlement、HealthKit 授权/选择、锁、onboarding、通知权限或其他设备权限。
- Delete All Data 有明确不可撤销确认，并清理本机模型、队列、快照和可识别的本 App Health 写入范围。

审核状态：核心/篡改/白名单/merge/replace/rollback 路径已有测试；最终 candidate 需重跑导出/备份/删除并保留 MP4/截图。

## 11. Shortcuts、Widget、Watch 和通知

- App Intents 支持记录经期流量和心情；Widget/跨进程队列采用 peek → save → acknowledge，保存失败不丢记录。
- Widget snapshot 和 WatchConnectivity 只传必要 kind/raw/dayKey/timestamp 等字段，不传私有备注正文。
- Apple Watch App、Widget、complication 和 Smart Stack 的代码路径与 generic build 可检查；没有实体证据时只能写 simulator-only/未测试。
- UserNotifications 只在用户从设置主动选择后排程；避孕 daily reminder 只对 pill 且已打开开关有效，通用本地通知不代表服务器推送。

审核状态：代码/队列测试已审计；实体 Shortcuts/Widget/Watch/通知交互仍属待测项。

## 12. Premium、StoreKit 和购买路径

- StoreKit 2 从 storefront 加载 monthly、yearly、lifetime 产品；价格、币种和周期由 Apple 返回，不在资料中硬编码价格。
- 已验签且仍有效的交易才授予同一 Premium entitlement；启动、前台、交易更新和 Restore Purchases 会重新核对，UserDefaults 不是授权来源。
- 付费墙可从 Trends 唯一 Premium 汇总卡、Settings > Maren Premium、Settings > Pro Advanced Reminders 和添加第 4 个自定义 Tracker 到达。
- Paywall 提供购买、Restore Purchases、Privacy Policy、Terms、管理订阅和自动续订/取消说明。
- 本审计不声称真实 Sandbox/TestFlight 购买、恢复、上传或 App Store Connect product 状态已完成；这些必须有实际证据。

审核状态：代码与静态 StoreKit 配置已审计；实体/沙盒购买和恢复保持 PENDING。

## 13. 区域、外部服务和内容权利

- 英文和 Simplified Chinese 功能、教育内容和免责声明保持同一逻辑；独立 Maestro 已通过 Education、Contraception、Reproductive tests、HealthKit English localization、简体中文 Today/Tracker 布局及英文 Trends/Library UI 2.0，且最终英文流程未出现中英混排；系统权限文字随设备语言，StoreKit storefront 决定价格/税/可用性。
- 无开发者后台、CloudKit 健康同步、第三方认证、广告、分析、数据经纪、第三方支付或 AI 服务。
- 使用的 Apple 平台为 SwiftData、StoreKit 2、HealthKit、UserNotifications、LocalAuthentication、App Intents/WidgetKit、App Groups、WatchConnectivity 和 Files。
- 静态网站只承载 Privacy Policy、Terms 和支持页面，不承载用户健康数据或 Premium 逻辑。
- 图标、截图、界面/教育文案和 supportive-message/quote library 的原创/授权状态须由开发者逐项确认；模板不能代替签名权利声明。

## 14. 自动化、设备和提交状态

- 当前最终 `1.1.0 (5)` candidate 的 iPhone 17 / iOS 26.5 simulator 全量测试为 286 tests、0 failures；仍不替代 physical iPhone 12 evidence。xcresult 为 `Evidence/Vela-v1.1-final-tests-286.xcresult`。
- 已核验并保存 `../Builds/Maren-1.1.0-5/Maren-v1.1.0-b5.xcarchive` 与 `../Builds/Maren-1.1.0-5/Maren.ipa`，App Store export succeeded；四个 bundle 均为 `1.1.0 (5)`，release profile/signing 含 `group.cd.cc.vela`，主 App 含 HealthKit，`get-task-allow=false`。
- Jufei iP12（iPhone 12）当前状态是 iOS 26.6（23G71）设备发现、未安装/未功能测试；必须升级到 iOS 26.6.1 或录制当天当前公开版本后重新录制。
- iPhone Air 不可用、未测试；不存在可用于审核回复的 iPhone Air 实体证据。
- 实体购买、上传、HealthKit/通知/Face ID 授权、实体 Watch 和最终 accessibility 走查均以 `05-Test-Matrix.csv` 的证据为准；本资料不声称最终实体录屏或 App Store Connect 上传已完成。
