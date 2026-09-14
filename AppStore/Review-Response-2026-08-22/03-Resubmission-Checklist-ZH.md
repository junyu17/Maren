# Maren 1.1.0 (8) 重新提交 Checklist

> 规则：所有未有实际 build-8 证据的项目保持 `PENDING`。当前已完成的本地自动化、构建、归档、IPA 和签名证据可以标记为已完成，但模拟器证据不能替代实体机证据；不要把历史 build-7 或更旧证据改写成 build-8 证据。

## A. 候选版本与工程

- [x] 已确认候选版本为 `1.1.0`，build 为 `8`；四个 bundle（主 App、Widget、Watch、Watch Widget）版本号均为 `1.1.0 (8)`。
- [x] 已用当前 `project.yml` 运行 `xcodegen generate` 并生成 `Vela.xcodeproj`。
- [x] Debug 测试构建通过；命令、Xcode/SDK、destination 和结果保存在最终 `.xcresult`。
- [x] build-8 全量测试通过：397/397 tests passed、0 failures；Xcode `26.6 (17F113)`、Vela Review iPhone 17 simulator / iOS `26.5`，`.xcresult` 为 `Evidence/Build8/Vela-1.1.0-8-full-tests.xcresult`。该模拟器证据不替代实体机测试。
- [x] Release iOS scheme 与 VelaWatch scheme 构建成功，覆盖四个 target；archive 为 `../Builds/Maren-1.1.0-8/Maren-v1.1.0-b8.xcarchive`。
- [x] IPA 导出成功：`../Builds/Maren-1.1.0-8/Maren.ipa`；SHA-256 为 `acdb4c97fd294939e758ea499b25b9149d80c74cb22fb9f681f72d6d5526515c`。
- [x] 已核验 release 包 `get-task-allow=false`、Apple Distribution / Jun Yu / team `255R6QQR97` 签名，且 codesign strict/deep 通过。
- [x] 已核对 release 包最低系统版本：iOS App/Widget 为 iOS 17.0，Watch App/Watch Widget 为 watchOS 10.0。
- [x] 已核验 App、Widget、Watch、Watch Widget 四个 bundle 的 App Group 均为 `group.cd.cc.vela`，不是测试值。
- [x] 已从最终分发 IPA 检查 HealthKit capability、Info.plist 使用说明、App Intents、WidgetKit 和 WatchConnectivity 嵌入关系；严格/深层 codesign 校验通过。
- [ ] `PENDING` 在 iPhone Air / iOS 26.6.1 和 iPhone 12 / iOS 26.6 重新安装并确认精确 build 8。

## B. 实体机与录屏

- [x] 实体测试设备清单已确认：iPhone Air / iOS 26.6.1；iPhone 12 / iOS 26.6。
- [x] Review Notes 已按 Apple 要求写入并保存上述两台实体设备和系统版本。
- [ ] `PENDING` 从实体机桌面开始录屏，文件名、时长、分辨率和 SHA-256 记录在矩阵。
- [ ] `PENDING` 录屏覆盖启动、Today、Calendar、创建/修改/删除、History 左滑删除和实时更新。
- [ ] `PENDING` 录屏覆盖自定义 Tracker label/emoji 编辑、key/历史保留和删除。
- [ ] `PENDING` 录屏覆盖免费 Perimenopause 30/90 record summary，并明确它不是 Premium 高级洞察或医疗诊断。
- [ ] `PENDING` 录屏覆盖 Daily Stories / personalized educational card / Library。
- [ ] `PENDING` 录屏覆盖全局离线搜索：文章、追踪项、药物、每日记录和经期日期的结果及精确跳转；删除结果实时消失。
- [ ] `PENDING` 录屏覆盖 HealthKit 七种类型、授权弹窗、步数和 Apple Exercise Time 只读语义。
- [ ] `PENDING` 录屏覆盖本地通知、Face ID/设备密码、系统/浅色/深色、字体大小。
- [ ] `PENDING` 录屏覆盖 Widget、App Shortcut 和可用的实体 Apple Watch；不可用时如实保留 PENDING。
- [ ] `PENDING` 录屏覆盖月度、年度、终身付费墙、年度七天试用资格文案、恢复购买和管理订阅。
- [ ] `PENDING` 录屏末尾覆盖 Delete All Data 完整确认和真实删除结果；只使用可销毁测试数据。
- [ ] `PENDING` 录屏没有真实健康资料、付款卡、Apple ID 密码或个人通知。

## C. Apple Review Information

- [x] `01-Apple-Review-Reply-EN.md` 已更新为 build 8；`07-ASC-Review-Notes-EN.txt` 保留 Apple 要求的设备/OS 清单，必须在提交前完成精确 Build 8 复测。
- [x] Review Notes 已提供无账号路径，明确无注册、登录、样例文件和 reviewer credentials。
- [x] Review Notes 已说明 UGC 仅为本机私有记录，无公开社区、评论、消息、举报或屏蔽系统。
- [x] Review Notes 已说明 HealthKit 七类数据和读写/只读边界，并与 App Privacy 一致。
- [x] Review Notes 已说明无开发者服务器、无第三方登录、无广告、无 analytics、无 AI 服务。
- [x] Review Notes 已说明地区一致性，仅 StoreKit 价格/税/币种/试用资格和系统语言因地区变化。
- [x] Review Notes 第 7 点已确认 App 不属于受监管临床服务，也不分发受保护的第三方媒体目录；因此无需专业资质或第三方内容凭证。
- [x] Review Information 已填入开发者联系电话和邮箱，没有内部占位符。

## D. StoreKit / App Store Connect IAP

- [x] 已创建并核对订阅组：Maren Premium。
- [x] 已核对 `cd.cc.vela.premium.monthly`：auto-renewable，1 month，US `$3.99`，无试用承诺。
- [x] 已核对 `cd.cc.vela.premium.yearly`：auto-renewable，1 year，US `$29.99`，eligible new subscribers 的 7-day introductory offer。
- [x] 已核对 `cd.cc.vela.premium.lifetime`：non-consumable，US `$69.99`，一次性永久有效，无续费。
- [x] 三个产品已设置名称、描述、价格、可售地区和本地化；最终税费、币种和资格仍由 Apple storefront 决定。
- [x] 已上传 IAP review screenshot 和 review notes，并说明每个产品在 App 内的导航路径。
- [ ] `PENDING` Sandbox/TestFlight 验证首次年订阅显示七天试用；非资格账户必须显示实际 StoreKit 状态，不强行承诺试用。
- [ ] `PENDING` Sandbox/TestFlight 验证购买、pending、取消、恢复、过期/降级和自动续费说明。
- [ ] `PENDING` 验证 paywall、Settings、Trends、Advanced Reminders、custom Tracker limit 都打开同一个购买入口。
- [ ] `PENDING` 验证 Restore Purchases 结果准确，不用本地 UserDefaults 假造 Premium 权益。

## E. 隐私、法律与 App Privacy

- [x] `AppStore/privacy-policy.md` 已明确 HealthKit step count 和 Apple Exercise Time 只读，以及无开发者健康数据服务器。
- [x] 已发布 `docs/privacy.html` 和 `docs/index.html`，三个公共 URL 均返回 HTTP 200。
- [x] App Store Connect Privacy Policy URL 为 `https://junyu17.github.io/Maren/privacy.html`。
- [x] EULA/Terms URL 为 `https://junyu17.github.io/Maren/terms.html`。
- [x] App Privacy 已发布为 `Data Not Collected`，与无账号、无 analytics/广告/追踪和本地 HealthKit 处理一致。
- [x] HealthKit usage descriptions 与七类型及读写/只读行为一致。
- [x] 年龄分级、儿童隐私、医疗免责声明、导出/备份不加密提示已与实际功能核对。
- [x] 隐私网页没有声称开发者收集 entitlement、支付信息或健康数据。

## F. 内容、素材和元数据

- [x] Review Notes 已声明教育文字、Daily Stories、界面素材和截图为原创、委托或依法授权，且不包含受保护的第三方媒体目录。
- [x] App Store icon、截图和宣传文案按无受保护第三方素材的产品边界提交。
- [x] ASC 已替换 9 张当前 UI 截图；Build 8 仅修改数据查询边界，无界面或功能入口变化，截图仍准确反映 Build 8。
- [x] App description 已统一“免费 Perimenopause 30/90 record summary vs Premium advanced insights”。
- [x] 所有 IAP 文案已统一“年/月自动续费；终身一次性；年订阅符合资格时七天试用”。
- [x] 中英文标题、功能名、Privacy Policy、Terms、Support URL 已检查并可打开。

## G. 最终提交流程

- [ ] `PENDING` ASC Build 8 Processing 完成后，把 iOS App 1.1.0 从 Build 7 切换为 `1.1.0 (8)`。
- [x] Xcode 官方 export/upload 已成功：2026-08-24 05:00 Pacific；日志明确 `EXPORT SUCCEEDED`、`Upload succeeded`、`Uploaded Vela`、`Uploaded package is processing`。
- [ ] `PENDING` App Store Connect Processing 完成且 build `1.1.0 (8)` 已绑定；本地归档的四个 bundle、签名、App Group、HealthKit 和 `get-task-allow=false` 已核对通过。
- [x] 已上传/绑定 IAP metadata、review screenshot、订阅组、价格和年度七天 introductory offer；四个 IAP/订阅组项目已加入 Draft Submission。
- [ ] `PENDING` 附上实体机录屏和 reviewer instructions。
- [x] 已填完 App Privacy、age rating、export compliance、content rights 和 Review Information；提交前仍应核对联系电话可接听。
- [ ] `PENDING` 做一次“从新安装到删除全部数据”的最终 walkthrough；不要只依赖自动化测试。
- [ ] `PENDING` 由第二位审阅者逐项核对 Apple Review Reply、录屏、矩阵和实际包内容。
- [ ] `PENDING` 只有所有阻塞项完成后，才点击 Submit for Review。

## 明确不应写成已完成的事项

最终录屏上传、精确 Build 8 实体机复测、录屏中的真实权限/IAP 展示和最终 Submit for Review 仍保持 `PENDING`。Review Notes 第 2–8 点、IAP/订阅组绑定和年度 7 天 introductory offer 配置已完成；Xcode 官方 ASC upload、build-8 automated tests、Release build/archive、IPA export 和签名/App Group 检查也已有证据。
