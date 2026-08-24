# 已归档的 build 2 清单 - 不要用于提交

> 当前 build 3 清单：`AppStore/Review-Response-2026-08-21/03-Resubmission-Checklist-ZH.md`。

审计日期：2026-08-14

> **2026-08-14 更新（CloudKit 处置结论）**：原 P0 中的 CloudKit 健康数据同步已在仓库内**移除完成**——
> 代码（`VelaApp` 纯本地配置、`CloudSync.swift` 删除）、entitlements（`project.yml` / `Vela.entitlements` 去掉 iCloud/CloudKit）、
> 设置页开关/提示、官方文档与审核回复均已同步。`CURRENT_PROJECT_VERSION` 已升至 `2`。下文 P0 第一项已标记为✅ 已解决。

## 一、当前结论

代码已具备重新提交条件（Simulator Debug build 与签名 Release archive 可完成），但**仍不建议立即提交**，直到下列项完成。

### P0（原）1：健康数据 CloudKit / iCloud 合规 —— ✅ 已解决（2026-08-14）

- **处置**：本次版本已移除健康数据 CloudKit 同步。删除了 iCloud/CloudKit capability、设置开关、CloudKit 配置路径，以及官网、隐私政策、条款、商店描述和审核回复里的 iCloud 健康数据同步承诺。保留本地 SwiftData、HealthKit、导出和 Watch/Widget 本机能力。
- **现状核对**：`VelaApp` 恒定使用本地 `ModelConfiguration`（无 cloudKitDatabase）；启动不再调用 `CloudSync`；设置页无「iCloud 同步」区块、无「需要重启」提示、无账户状态校验任务；`Vela.entitlements` 仅剩 App Groups + HealthKit。仓库内已无可用的 `CloudSync` 引用。
- **配合动作**：
  - `CURRENT_PROJECT_VERSION` 已从 `1` 升到 `2`（保持 `MARKETING_VERSION 1.0.0`）。
  - 三份英文/简中隐私・条款与官网已改为「数据只存本机、无 iCloud/CloudKit」。
  - 中文回复/录屏/审计清单已改述为「无 CloudKit 的 build 2」。
  - **剩余人工步骤**：开发者门户 App ID 确认不勾 iCloud capability；老截图若含 iCloud 承诺不再使用；重新 Archive/TestFlight/实体机录屏。

> 不要在回复里用“CloudKit private therefore compliant”作结论 —— 该功能已不在 build 中。

### P0（原）2：实体机录屏和实体机完整测试未完成

本机发现：

- `Jufei iP12`：iPhone 12，iOS 26.6，Developer Mode 已开启，但设备处于网络 tunnel 断开/需要解锁状态。
- `Billys17Air`：iPhone Air，iOS 26.6，离线。

最新一次（2026-08-14）检查中，`devicectl list devices` 一度把 iPhone 12 标为 `available (paired)`，但实际执行 build 2 安装时仍立即失败：`The tunnel connection failed ... com.apple.dt.RemotePairingError error 4`。因此目前只能确认型号、系统和配对状态，不能写“full flow passed”。请保持 iPhone 解锁、与 Mac 在同一网络或以 USB 连接，直到 Xcode Devices and Simulators 显示稳定可用后再重试。**此项仍为提交前必做，未完成。**

### P1（原）：英文字符串缺失 —— ✅ 代码侧已解决

已补全原审计发现的插值字符串、付费墙订阅披露与“管理订阅”的英文/简中翻译，并补齐 Info.plist 的简中显示名。`AppStore/patch_catalog.py` 已改为只读审计工具，不再执行会覆盖工作区并重新引入旧 iCloud 文案的 `git checkout`。当前审计结果为：除品牌名 `Maren` 外，`Localizable.xcstrings` 与 `InfoPlist.xcstrings` 的 `en` / `zh-Hans` 条目完整；最终 Release Archive 已成功编译两种语言资源。

仍须在英文实体机实际走到插值页面；代码与目录完整不等于实体机排版已经验收。

### P1：缺少 IAP 审核截图和真实 Sandbox/TestFlight 证据

`AppStore/screenshots/` 目前有日历、趋势、今天、隐私、阶段和 Watch 截图，但未发现独立的付费墙截图。三个 IAP 的 Review Information 都需要上传能看清购买位置和价格/周期的截图，可复用同一张完整付费墙截图。

本地 `Maren.storekit` 与 StoreKit 2 代码不等于 App Store Connect 产品已经 Ready to Submit，也不等于 TestFlight Sandbox 交易已经通过。必须逐项验证：

- `cd.cc.vela.premium.yearly`
- `cd.cc.vela.premium.monthly`
- `cd.cc.vela.premium.lifetime`
- 购买成功立即解锁。
- 取消购买不解锁且无误导错误。
- pending 状态有明确提示。
- 恢复购买在新设备/重装后能恢复。
- 订阅过期、退款或撤销后能降级。

### P1：内容权利来源尚未闭环

项目立项书里的“每日一句词库来源（自写 / 授权 / AI 生成后人工审）”仍是未勾选状态。`quotes.json` 有大量中英文短句。它们不是带作者署名的经典引用，但重新提交前仍应由开发者确认：

- 全部是原创、受委托创作、合法授权，或可合法使用的生成内容。
- 没有逐句复制竞品、书籍、影视台词、歌词或社交媒体内容。
- App 图标和截图素材也由开发者拥有或有授权。

确认后签署 `04-Content-Rights-Declaration-Template-EN.md` 作为备查；Apple 未要求时不一定需要主动上传。

### P1：build 号

原归档为 `1.0.0 (1)`。**已按 CloudKit 移除 + 本地化补全将 `CURRENT_PROJECT_VERSION` 升至 `2`（2026-08-14），重新 Archive/上传时必须提交 `1.0.0 (2)`。**同一版本号可以继续用，但 build number 必须高于已上传过的 build。

## 二、实际功能遍历结果

### 1. 启动和导航

- 四页 onboarding：隐私优先、本地数据、自适应周期、快速记录。
- 四个主标签：日历、今天、趋势、设置。
- Widget deep link：小组件进入日历，中号组件进入今天。
- 可选 Face ID/Touch ID/设备密码锁；切后台时隐私快照打码并重新上锁。

### 2. 日历与预测

- 月份前后切换、地区化星期顺序。
- 点日期标记/修改/清除经期和四档流量。
- 实际经期、预测区间、卵泡期、排卵期、黄体期颜色。
- 周期阶段科普页与明确医学/避孕免责声明。
- 自动预测基于周期起点间隔，支持 15–120 天，不写死“第 14 天”。
- 支持手动周期长度与经期长度。
- 历史不足时明确提示继续记录。

### 3. 今天记录

- 日期选择、每日一句。
- 心情、能量、疼痛、睡眠、体重。
- 内置症状/追踪项和自定义追踪项。
- 私有备注。
- 今日用药打卡。
- 空白记录不会写入数据库；清空已有草稿后保存会删除该日空记录。

### 4. 趋势

免费：

- 历史周期列表。
- 周期长度图。

Premium：

- 个性化洞察（纯本机统计）。
- 近 30 天心情趋势。
- 有数据时显示体重趋势。
- 追踪项频次。

### 5. 用药与提醒

免费：

- 用药/补剂增删改。
- 单个每日提醒。
- 每日记录提醒。
- 经期前 2 天提醒。

Premium：

- 每个用药多个时段。
- 按周几排程。
- 经期提前 1–5 天自定义。
- PMS/黄体期关怀提醒。
- 基于个人记录的阶段智能提醒。

通知全部由 UserNotifications 在设备本地生成。代码考虑了 iOS 最多 64 条 pending local notifications 的上限并给用户提示。

### 6. Premium 与 IAP

三个产品解锁同一 Premium entitlement：月订阅、年订阅、终身 Non-Consumable。价格与周期从 StoreKit 读取，购买后按已验签 transaction 立即授予；启动和交易更新时重新检查；有恢复购买入口。

Premium 还包括：5 套主题、超过 3 个的无限自定义追踪项、高级提醒和高级趋势。

PCOS 一般科普页本身是免费内容；审核回复不得把“PCOS 科普页”说成只有 Premium 才能访问。可准确描述为“Premium 提供适用于 PCOS/不规律周期用户的体重趋势、无限自定义项和个性化洞察”。

### 7. 数据与隐私

- 默认 SwiftData 本地存储。
- 无 Maren 账号、无注册、无登录。
- 无公开 UGC、社区、私信、举报或屏蔽需求。
- CSV/PDF 导出覆盖经期、每日记录、用药、用药打卡、自定义追踪项。
- 设置内“删除所有数据”覆盖全部 5 类模型、提醒、Widget 快照和手动周期设置。
- 无第三方广告、分析或 AI SDK。
- ✅ **已移除 CloudKit 私有同步（见 P0）**；健康数据纯本机本地库，无跨设备同步。

### 8. 权限

- HealthKit：只请求 menstrual flow 读写。
- UserNotifications：本地通知。
- LocalAuthentication：Face ID/Touch ID/设备密码。
- 无 Location、Contacts、Camera、Microphone、Photos、ATT。

### 9. Widget 与 Watch

- Widget：systemSmall/systemMedium，显示阶段、提示、下次经期和每日一句；点击回 App。
- Watch：显示快照，快速记录经期流量和心情，通过 WatchConnectivity 回传 iPhone。
- Release archive 已包含 Watch app、Watch icon、Widget extension 和三份 PrivacyInfo.xcprivacy。

## 三、已完成验证

- [x] iPhone 17 simulator / iOS 26.5 Debug build 成功。
- [x] Simulator fresh launch，英文 onboarding 正常显示。
- [x] generic iOS Release archive 成功。
- [x] Archive 内主 App、Widget、Watch 的版本号均为 `1.0.0 (2)`。
- [x] Archive 内主 App、Widget、Watch 均包含 `PrivacyInfo.xcprivacy`。
- [x] Watch bundle 的 `CFBundleIcons > CFBundlePrimaryIcon > CFBundleIconName=AppIcon`、`WKApplication=true`、companion bundle ID 正确。
- [x] Archive `codesign --verify --deep --strict` 通过。
- [x] Archive 主 App 的实际签名权限仅含 App Groups、HealthKit 和团队标识；无 iCloud/CloudKit entitlement。
- [x] 英文/简中字符串目录只读审计通过，最终 Archive 已编译两种语言资源。
- [x] 主站、隐私政策、条款 URL 均返回 HTTP 200。
- [x] App icon、iPhone 截图和 Watch 截图尺寸已读取并符合现有目录标注。

尚未完成：

- [ ] iPhone 12 / iOS 26.6 实体机安装、启动和全流程。
- [ ] iPhone Air / iOS 26.6 实体机兼容性。
- [ ] 实体 Apple Watch / watchOS 26.6。
- [ ] HealthKit 实体机授权、导入和写回。
- [ ] Face ID 实体机。
- [ ] 通知实体机触发。
- [ ] TestFlight/Sandbox 月、年、终身购买与恢复。
- [x] Apple 5.1.3(ii) CloudKit 决策 ✅ 已落地：CloudKit 已移除，build 2 无 iCloud/CloudKit。
- [ ] 英文本地化补全后的实体机复测（目录与 Archive 已通过）。
- [ ] 内容权利确认。

## 四、App Store Connect 重新提交资料

### App Review Information

- [ ] Contact first/last name。
- [ ] 可接听电话。
- [ ] `billy.yu@me.com`。
- [ ] Sign-in required：No。
- [ ] Notes：粘贴 `01-Apple-Review-Reply-EN.md` 的精简版或上传全文附件。
- [ ] 上传实体机录屏 MP4。
- [ ] 如 Apple 有 Resolution Center 对话，在同一对话中回复后再 Resubmit。

### Build

- [x] CloudKit/本地化处理 ✅（2026-08-14 完成：代码、entitlements、设置开关、文档、本地化均已改）。
- [x] `CURRENT_PROJECT_VERSION` 升到未用过的新值（1 → 2）。
- [x] `xcodegen generate` 后三 target 配置一致。
- [x] Release Archive（本地签名归档已成功；仍需 Organizer Validate/上传）。
- [ ] Organizer Validate App。
- [ ] Upload。
- [ ] 等待 Processing 完成并选择新 build。

### IAP

- [ ] 年订阅：`cd.cc.vela.premium.yearly`，1 year。
- [ ] 月订阅：`cd.cc.vela.premium.monthly`，1 month。
- [ ] 两个订阅同组、同 level。
- [ ] 终身：`cd.cc.vela.premium.lifetime`，Non-Consumable。
- [ ] 各产品地区可用性和价格已保存。
- [ ] 英文与简中 display name/description。
- [ ] 三个产品各上传付费墙 Review Screenshot。
- [ ] Review Notes 写明三个产品解锁同一 entitlement、无账号、恢复购买路径。
- [ ] 首次订阅组和订阅与新 App 版本同一次提交。

### 商店元数据

- [ ] 描述里的免费/Premium 权益与当前代码一致。
- [ ] 不把 PCOS 科普页写成 Premium 独占。
- [ ] 无“精准排卵”“安全期”“避孕保证”等表述。
- [ ] Privacy Policy URL：`https://junyu17.github.io/Maren/privacy.html`。
- [ ] Terms URL：`https://junyu17.github.io/Maren/terms.html`。
- [ ] Support URL：`https://junyu17.github.io/Maren/`。
- [ ] 如果已移除 CloudKit（✅ 已移除），README、官网、Privacy、Terms、App description、Review Notes 和截图中的相关文字须已同步修改（仓库内文档已改；✓ 待复核已托管页面与截图）。
- [ ] App Privacy 问卷与最终 binary 一致。纯本机处理的数据按 Apple 定义不是 collected；build 2 无 CloudKit、无网络层，选择 `Data Not Collected`。
- [ ] Content Rights 选择与每日一句、图标、截图素材的真实权利状态一致。

### 屏幕截图与附件

- [ ] iPhone 6.9 英寸现有截图复核为最终 UI。
- [ ] 如果最终版本移除 iCloud，不能继续使用出现 iCloud 承诺的旧截图。
- [ ] 重新截取隐私/设置截图：build 2 已把笼统的“数据永不离开设备”改为准确披露 Export、Apple Health 和配对 Apple Watch 的用户主动路径，旧 `4_privacy.png` 不应直接复用。
- [ ] 新增清晰付费墙截图。
- [ ] Watch screenshot 只有在 Watch app 仍提交且已完成相应测试时保留。
- [ ] 录屏文件可播放，开头从点击 App 图标开始。

## 五、发送前最后三次检查

1. **需求匹配检查**：Apple 要求的每一条都在英文回复中有明确答案，录像覆盖账号/IAP/UGC/权限的适用或不适用说明。
2. **独立正确性检查**：英文回复、隐私政策、商店描述、代码行为、entitlements、IAP 产品和录像完全一致。
3. **真实产物检查**：打开最终 MP4、最终 Archive/TestFlight build、最终 URL 和 App Store Connect IAP 状态逐一确认；保留 build number、TestFlight build ID、测试日期和设备信息。
