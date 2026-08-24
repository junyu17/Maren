# Maren 重新提交检查清单（1.1.0 build 5）

## 当前结论和证据边界

- [x] 代码已包含 106 项、10 类可搜索 Tracker、设备端 Today Status、排卵/妊娠测试只记录、当地避孕记录/药丸每日提醒、HealthKit 步数/Apple 锻炼时间只读导入、知识库、每日 Daily Story、围绝经期模式及 30/90 日记录趋势。
- [x] 既有经期/流量、每日记录、用药/打卡、预测范围、趋势、导出、加密备份、删除、Shortcuts/Widget/Watch 数据路径和 IAP 代码保持在资料范围内；所有医学/避孕结论均排除。
- [x] 最终 `1.1.0 (5)` candidate 的 iPhone 17 / iOS 26.5 simulator 全量测试为 286 项、0 failure；仍是 simulator-only，不是实体机证据。xcresult：`Evidence/Vela-v1.1-final-tests-286.xcresult`。
- [x] 独立 Maestro 已通过 Education、Contraception、Reproductive tests、HealthKit English localization、简体中文 Today/Tracker 布局及最终英文 Trends/Library UI 2.0 流程；已覆盖的英文流程未出现中英混排。
- [x] 已核验并保存 `../Builds/Maren-1.1.0-5/Maren-v1.1.0-b5.xcarchive` 与 `../Builds/Maren-1.1.0-5/Maren.ipa`，App Store export succeeded；四个 bundle 均为 `1.1.0 (5)`，release profile/signing 含 `group.cd.cc.vela`，主 App 含 HealthKit，`get-task-allow=false`。
- [ ] TestFlight 安装、实体机录屏和 App Store Connect build 选择尚未由本资料声称完成。
- [ ] 未声称实体购买/恢复、HealthKit 授权、通知授权、Face ID 或实体 Apple Watch 已完成。

## 实体设备与系统

- [ ] Jufei iP12（iPhone 12）当前记录为 iOS 26.6（23G71），仅完成设备发现，未安装/未测试 App。
- [ ] Apple 已于 2026-08-17 发布 iOS 26.6.1；录屏前升级 iPhone 12 并再次确认版本。官方公告：<https://support.apple.com/en-us/148282>。
- [ ] iPhone Air 不可用、未测试，不得出现在录屏附件或“已测试设备”描述中。
- [ ] 实体 Apple Watch 只有在有实际视频/截图后才可填写 PASS；否则保持 PENDING 或写 simulator-only。
- [ ] 每行测试矩阵包含日期、build `1.1.0 (5)`、型号、OS、语言/地区、安装来源、范围、结果、证据和测试人。

## Binary、签名和隐私

- [ ] `xcodegen generate` 后检查工程与 `project.yml` 一致；不得用生成操作掩盖 source/config 变化。
- [x] 已生成并验证 `1.1.0 (5)` signed archive 与 App Store IPA；App Store export succeeded。实体录屏和上传仍需独立证据。
- [ ] 主 App、iOS Widget、Watch App、Watch Widget 的 entitlements 与 PrivacyInfo.xcprivacy 逐一从最终 archive 检查。
- [ ] App Privacy、出口合规、年龄分级、内容权利和 HealthKit 用途按最终 binary 填写。
- [ ] `.marenbackup` UTI、文件导入/导出、临时文件保护和不自动上传的描述与最终 binary 一致。

## v1.1 功能核对

- [ ] Today > Symptoms & Trackers 展示 106 个内置 Tracker，按 10 类分组，可搜索标签/键；自定义项仍是本机记录，不是公共 UGC。
- [ ] Today Status 只展示最多 3 条设备端观察和数据不足状态；不诊断、不预测疾病、不生成治疗或避孕建议。
- [ ] Reproductive tests 可记录排卵测试 None/Negative/Positive/Peak、独立 Manual ovulation，以及妊娠测试 None/Negative/Positive/Invalid；页面明确“只记录结果”。
- [ ] Settings > 避孕记录只保存本机方法、可选开始日期/备注和提醒偏好；只有 Pill 显示每日提醒时间；不写有效性、漏服、诊断或医疗建议。
- [ ] Settings > Library 可搜索、按分类浏览、打开来源/非医疗说明并收藏本地文章。
- [ ] Today 展示按用户记录、阶段和主动选择的围绝经期模式确定性选择的 Daily Story/教育卡；不把个性化选择描述成临床判断。
- [ ] 用户主动选择 **Settings > Tracking context > Perimenopause** 后，Trends 可免费进入 30/90 日记录摘要；录屏需明确无诊断。Premium 订阅信息、购买/恢复通过独立汇总卡展示。

## Apple Health 权限与数据流

- [ ] Apple Health 选择页逐类展示 7 类：经期流量、体重、睡眠分析、基础体温、点滴出血、步数、Apple 锻炼时间。
- [ ] 授权只从用户主动选择的 Settings 入口触发；不在启动或无关页面自动请求。
- [ ] 经期流量、体重、基础体温、点滴出血可按用户选择读写；睡眠、步数、Apple 锻炼时间只读导入。
- [ ] Health 数据只在本机与 Apple Health 之间处理；不发送到 Maren 开发者服务器，不用于广告或第三方分析。
- [ ] 导入来源标记、手工值优先、过滤 Maren 自己写入的样本、关闭同步不冒充撤销权限等行为由代码/测试和实体机证据分别核对。

## 既有核心功能和数据安全

- [ ] 日历经期/流量、清除、周期估算范围和阶段教育都显示非医疗、非排卵/避孕保证声明。
- [ ] 每日心情、能量、疼痛、睡眠、体重、基础体温、点滴出血、备注、用药及打卡可创建/修改/清空。
- [ ] Sample Experience 只读、隔离，不写真实 SwiftData；退出后真实记录数量不变。
- [ ] 临床 PDF 与原始 CSV/PDF 生成前均提示文件未加密；加密备份密码不保存、不上传且不可恢复。
- [ ] 备份导入先校验并在单次保存失败时 rollback；默认 Merge，Replace 有破坏性二次确认；不恢复 Premium、HealthKit 授权/选择、锁或系统权限。
- [ ] Delete All Data 只删除本机记录和本 App 可识别的本地/HealthKit 写入范围，并提示不可撤销。
- [ ] Shortcuts、交互式 Widget、WatchConnectivity 只传必要的快速记录字段，不传私有备注正文；无账号、登录、社区、公开个人资料、私信或公共 UGC。

## 本地化、区域和外部服务

- [x] 独立 Maestro 已覆盖 Education、Contraception、Reproductive tests、HealthKit English localization、简体中文 Today/Tracker 布局和英文 Trends/Library UI 2.0；已覆盖的英文流程未出现中英混排。实体机完整路径仍需录屏。
- [ ] 功能与教育内容跨启用区域一致；StoreKit 名称、价格、币种、税和可用性由 storefront 返回，不写死美国价格。
- [ ] 只有 Apple 系统服务：SwiftData、StoreKit 2、HealthKit、UserNotifications、LocalAuthentication、App Intents/WidgetKit、App Groups、WatchConnectivity、Files。
- [ ] 无开发者后台、CloudKit 健康同步、第三方登录、广告、分析、数据经纪、第三方支付或 AI 服务；网站仅为静态支持/法律页面。

## IAP 和审核资料

- [ ] Paywall 可从 Trends 唯一 Premium 汇总卡、Settings > Maren Premium、Settings > Pro Advanced Reminders、添加第 4 个自定义 Tracker 等路径打开。
- [ ] Paywall 从 StoreKit 加载月订阅、年订阅、终身买断的本地化产品信息；价格/周期以 StoreKit 为准。
- [ ] 展示自动续订/取消、Apple 处理支付、Privacy Policy、Terms、管理订阅和 Restore Purchases；月/年同 subscription group、同 entitlement。
- [ ] 未有真实 Sandbox/TestFlight 购买/恢复证据前，矩阵和回复保持 PENDING；不得用本地 StoreKit 配置冒充实体购买。
- [ ] Review Information 联系电话、邮箱、Sign-in required、IAP review screenshot、Privacy URL、Terms URL 和内容权利声明均由开发者最终填写/确认。

## 发送前三次复核

1. 对照 Apple 审核问题、`01-Apple-Review-Reply-EN.md`、一镜到底视频和 `05-Test-Matrix.csv`，确认全部写的是 `1.1.0 (5)`。
2. 独立核对代码、最终 archive、StoreKit 产品、HealthKit 用途、隐私政策、商店文案、IAP entitlement 和所有免责声明。
3. 实际打开最终签名 archive/TestFlight、MP4、网站 URL、IAP 状态和证据文件；记录 build ID、设备升级结果和提交时间。
