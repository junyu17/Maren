# Maren 1.1 实体机审核录屏方案（build 5）

目标文件名：`Maren-App-Review-iPhone12-iOS26.6.1-v1.1.0-b5.mp4`

## 重要设备边界

- 当前可用实体 Jufei iP12（iPhone 12）的已知状态是 iOS 26.6（23G71），只完成设备发现，没有安装或功能测试。
- Apple 已于 2026-08-17 发布 iOS 26.6.1（官方公告：<https://support.apple.com/en-us/148282>）。录屏前必须升级 iPhone 12，并在“设置 > 通用 > 关于本机”记录实际版本；未升级前不得声称它是最新系统或已完成测试。
- iPhone Air 当前不可用、未测试，不得作为录屏设备，也不得在审核回复中写成已测试。
- 本方案不预先声称实体机购买、上传、HealthKit 授权、通知授权、Face ID 或 Apple Watch 已完成；只有视频和截图证据能改变矩阵状态。
- 当前本地候选证据已完成：286/286 XCTest、独立 Maestro 的 Education/Contraception/Reproductive tests/HealthKit 英文本地化、简体中文 Today/Tracker 布局以及最终英文 Trends/Library UI 2.0 流程；已覆盖的英文流程未出现中英混排。该证据不替代实体机录屏。

## 录制原则

- 使用实体 iPhone 12 和将要提交的同一个 `1.1.0 (5)` TestFlight/re-submission build；从主屏幕点击 Maren 开始。
- 开启专注模式、清空通知中心、使用纯演示数据；不要露出 Apple ID、邮箱、电话、序列号、真实健康记录或真实处方。
- 不使用 Xcode StoreKit 配置冒充 Sandbox/TestFlight 购买证据。若实际完成购买，连续录入购买结果；若未完成，只展示购买入口并在矩阵中保持 PENDING。
- 建议 10–14 分钟、一镜到底。关键系统弹窗、动态 StoreKit 价格周期和成功结果必须连续可读。

## 录制前必须完成

- [ ] 版本显示为 `1.1.0 (5)`，与 App Store Connect 选中的 candidate 完全一致。
- [ ] iPhone 12 已升级至 iOS 26.6.1 或录制当天的当前公开版本，并保存“关于本机”截图。
- [ ] 106 项内置追踪项、10 个分类、搜索、Today Status、排卵/妊娠测试记录、避孕记录、Library、Daily Story、围绝经期 30/90 日事实均可从 UI 到达。
- [ ] Apple Health 选择页可展示 7 类：经期流量、体重、睡眠、基础体温、点滴出血、步数、Apple 锻炼时间；睡眠/步数/锻炼时间明确为只读。
- [ ] 权限已重置；只从用户主动选择的入口触发通知、HealthKit、Face ID 系统提示。
- [ ] 原始 CSV/PDF 和临床 PDF 的“未加密”警告会出现；加密备份密码至少 8 位且无法恢复。
- [ ] Sandbox/TestFlight 月/年/终身购买和恢复若要写 PASS，必须各有真实证据；否则保留 PENDING。

## 一镜到底脚本

### 00:00–00:45 启动、隐私和状态

1. 从主屏幕点击 Maren，展示隐私、本地存储、估算限制、无账号/登录要求。
2. 进入 Today，展示设备端生成的 **Today Status**；空白时显示记录不足提示，不把观察写成诊断。

### 00:45–02:20 106 项 Tracker 与每日记录

1. 在 Today 的 Symptoms & Trackers 打开搜索，搜索一个内置标签；展开分类并展示 106 项内置追踪项和自定义项入口。
2. 记录心情、能量、疼痛、睡眠、体重、基础体温、点滴出血、症状、备注和用药打卡，保存并展示成功状态。
3. 说明 Tracker、Today Status 和所有统计都是用户记录的设备端描述，不是诊断或医学建议。

### 02:20–03:20 生殖测试记录（只记录）

1. 在 Today 展示排卵测试的 None/Negative/Positive/Peak，展示独立的 Manual ovulation 开关。
2. 展示妊娠测试的 None/Negative/Positive/Invalid。
3. 保持页面页脚免责声明清晰可读：只记录结果，不解释、不预测、不诊断，也不提供避孕指导。

### 03:20–04:10 本地避孕记录和提醒

1. 进入 Settings > 追踪与提醒 > 避孕记录，展示“未记录”和可记录的方法列表。
2. 选择 Pill，展示可选开始日期、备注和 Daily reminder/time；再切换到其他方法，证明每日提醒选项隐藏/关闭。
3. 展示保存成功提示。说明它只保存本机记录和提醒偏好，不提供有效性、漏服、诊断或医疗建议；组件本身不请求权限。

### 04:10–05:00 知识库与 Daily Story

1. 进入 **Settings > Library**，展示本地文章搜索、分类、来源/非医疗说明和收藏。
2. 回到 Today，展示当天 Daily Story/个性化教育卡；说明选择依据是本机记录、阶段和用户主动选择的模式，内容不等于诊断。

### 05:00–06:00 围绝经期模式与 30/90 日记录趋势

1. 在 **Settings > Tracking context > Perimenopause** 选择 Perimenopause；不展示任何“自动判断”或医疗结论。
2. 进入 **Trends > Perimenopause summary**，切换 30 天与 90 天；说明这是免费的记录事实摘要，不是诊断。
3. 展示订阅信息、购买和 Restore Purchases；只有真实购买成功后才展示 30 days 和 90 days 报告、coverage、记录的症状日、周期长度事实、睡眠/心情平均值及数据不足提示。
4. 读出页面免责声明：这些是记录事实和观察性统计，不诊断，也不构成医疗建议。

### 06:00–07:10 Apple Health（只读字段边界）

1. 在 Settings > Apple Health 展示逐类选择和可选授权入口。
2. 说明经期流量、体重、基础体温、点滴出血可按用户选择读写；睡眠分析、步数、Apple 锻炼时间只读导入。
3. 若真实授权/导入已完成，展示来源标记；若未完成，停止在入口并保持矩阵 PENDING，不使用真实私人数据。

### 07:10–08:20 既有核心功能和 IAP 路径

1. 在 Calendar 展示经期/流量记录、基于个人记录的估算范围、阶段说明和非医疗/非避孕免责声明。
2. 展示 Trends 的免费周期历史与唯一一张 Maren Premium 汇总卡；从该卡或 Settings > Maren Premium 打开付费墙。
3. 展示 StoreKit 动态月订阅、年订阅、终身买断、恢复购买、Privacy Policy、Terms 和管理订阅入口。只有实际完成购买时才展示解锁结果。

### 08:20–10:10 导出、备份、快捷功能和删除

1. 展示原始 CSV/PDF、临床 PDF 的未加密警告并取消分享。
2. 导出 `.marenbackup`，输入至少 8 位密码；导入时展示版本/构建/记录数、默认 Merge 和需二次确认的 Replace，但不要覆盖真实数据。
3. 如已有实体证据，展示 Shortcuts、交互式 Widget 或 Apple Watch；没有证据就不在回复中声称实体测试。
4. 进入 Delete All Data，展示破坏性二次确认后取消；停留设置页证明无账号、无公共 UGC。

## 录屏验收

- [ ] 第一帧是实体 iPhone 12 主屏幕点击 App；设备、OS、版本/build、日期有截图或片头证据。
- [ ] 录屏明确展示 1.1 新功能：106 搜索 Tracker、Today Status、生殖测试只记录、避孕/药丸提醒、HealthKit 只读步数/锻炼、Library、Daily Story、免费的围绝经期 30/90 日记录事实，以及独立的 Premium 汇总卡与购买/恢复入口。
- [ ] 不出现 iPhone Air 已测试、iOS 26.6 已是最新、实体购买/上传/授权已完成等无证据陈述。
- [ ] 不出现真实个人健康数据；MP4 从头到尾可播放、文字清晰、系统弹窗完整。
- [ ] 视频、英文回复、中文矩阵、最终签名 candidate 的版本和功能完全一致。
