import SwiftUI
import SwiftData

/// Manual encrypted backup export/import UI.  The view owns only transient
/// passwords and encrypted bytes; the SwiftData coordinator owns all model
/// mutations after the user confirms an import.
struct BackupManagerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showExportPassword = false
    @State private var showImportPassword = false
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var showReplaceConfirmation = false
    @State private var showError = false
    @State private var canRetryImport = false
    @State private var errorMessage = ""
    @State private var isBusy = false

    @State private var exportPassword = ""
    @State private var exportConfirmation = ""
    @State private var importPassword = ""
    @State private var pendingImportData: Data?
    @State private var decryptedBackup: DecryptedBackup?
    @State private var exportDocument: MarenBackupDocument?
    @State private var importMode: BackupMergeMode = .merge

    private let engine = EncryptedBackupEngine()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        exportPassword = ""
                        exportConfirmation = ""
                        showExportPassword = true
                    } label: {
                        Label("导出加密备份", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        pendingImportData = nil
                        importPassword = ""
                        decryptedBackup = nil
                        showFileImporter = true
                    } label: {
                        Label("导入加密备份", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("手动备份")
                } footer: {
                    Text("备份包含本机记录和少量可迁移偏好,使用密码加密后保存在你选择的位置。密码无法恢复,请妥善保管。")
                }

                if let backup = decryptedBackup {
                    previewSection(backup)
                }
            }
            .navigationTitle("加密备份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay {
                if isBusy {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView("处理中…")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .sheet(isPresented: $showExportPassword) {
                exportPasswordForm
            }
            .sheet(isPresented: $showImportPassword) {
                importPasswordForm
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.marenBackup],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    readImportFile(from: url)
                case .failure(let error):
                    present(error)
                }
            }
            .fileExporter(isPresented: $showFileExporter,
                          document: exportDocument,
                          contentType: .marenBackup,
                          defaultFilename: "Maren-Backup") { result in
                exportDocument = nil
                if case .failure(let error) = result {
                    present(error)
                }
            }
            .confirmationDialog("确认替换本机数据?",
                                isPresented: $showReplaceConfirmation,
                                titleVisibility: .visible) {
                Button("替换并导入", role: .destructive) {
                    applyDecryptedBackup()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("替换会删除本机现有的经期、每日记录、用药、自定义追踪项和打卡历史,且无法撤销。")
            }
            .alert("备份操作失败", isPresented: $showError) {
                if canRetryImport {
                    Button("重试密码") {
                        canRetryImport = false
                        importPassword = ""
                        showImportPassword = true
                    }
                }
                Button("好", role: .cancel) {
                    canRetryImport = false
                }
            } message: {
                Text(errorMessage)
            }
            .onDisappear {
                clearTransientSecrets()
            }
        }
    }

    private var exportPasswordForm: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $exportPassword)
                    SecureField("确认密码", text: $exportConfirmation)
                } header: {
                    Text("设置备份密码")
                } footer: {
                    Text("密码至少 8 个字符。Maren 无法恢复或重置密码;忘记密码将无法导入备份。")
                }

                Section {
                    Button("开始导出") {
                        startExport()
                    }
                    .disabled(exportPassword.isEmpty || exportConfirmation.isEmpty)
                }
            }
            .navigationTitle("导出加密备份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showExportPassword = false
                        exportPassword = ""
                        exportConfirmation = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var importPasswordForm: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $importPassword)
                } header: {
                    Text("输入备份密码")
                } footer: {
                    Text("密码仅用于本次解密,不会保存或上传。")
                }
                Section {
                    Button("继续") {
                        decryptImportedFile()
                    }
                    .disabled(importPassword.isEmpty)
                }
            }
            .navigationTitle("导入加密备份")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showImportPassword = false
                        importPassword = ""
                        pendingImportData = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func previewSection(_ backup: DecryptedBackup) -> some View {
        let preview = backup.preview
        Section {
            LabeledContent("创建时间", value: formattedDate(preview.createdAt))
            LabeledContent("应用版本", value: preview.appVersion)
            LabeledContent("构建版本", value: preview.buildNumber)
            LabeledContent("数据格式", value: "Schema " + String(preview.schemaVersion))
            LabeledContent("经期记录", value: String(preview.counts.periodDays))
            LabeledContent("每日记录", value: String(preview.counts.dailyLogs))
            LabeledContent("用药", value: String(preview.counts.medications))
            LabeledContent("用药打卡", value: String(preview.counts.medicationIntakes))
            LabeledContent("自定义追踪项", value: String(preview.counts.customSymptoms))
        } header: {
            Text("备份预览")
        } footer: {
            Text("来源应用: \(preview.appIdentifier)。导入前请确认版本、构建号和记录数量。")
        }

        Section {
            Picker("导入方式", selection: $importMode) {
                Text("合并（推荐）").tag(BackupMergeMode.merge)
                Text("替换本机数据").tag(BackupMergeMode.replace)
            }
            Button(importMode == .replace ? "选择替换并导入" : "开始导入") {
                if importMode == .replace {
                    showReplaceConfirmation = true
                } else {
                    applyDecryptedBackup()
                }
            }
            .disabled(isBusy)
        } header: {
            Text("导入设置")
        } footer: {
            Text(importMode == .replace
                 ? "替换模式会删除本机现有记录,需要再次确认。"
                 : "合并模式保留本机较新的日期记录,并保留已有的用药、自定义项和打卡键。")
        }
    }

    @MainActor
    private func startExport() {
        do {
            try EncryptedBackupEngine.validatePassword(exportPassword,
                                                       confirmation: exportConfirmation)
        } catch {
            present(error)
            return
        }

        let snapshot: BackupSnapshot
        do {
            let coordinator = BackupImportCoordinator(context: context, engine: engine)
            snapshot = try coordinator.captureSnapshot(
                preferences: BackupPreferences.fromCurrentDeviceDefaults())
        } catch {
            present(error)
            return
        }

        let password = exportPassword
        exportPassword = ""
        exportConfirmation = ""
        showExportPassword = false
        isBusy = true

        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try engine.encrypt(snapshot, password: password))
                } catch {
                    return .failure(error)
                }
            }.value

            isBusy = false
            switch result {
            case .success(let data):
                exportDocument = MarenBackupDocument(data: data)
                showFileExporter = true
            case .failure(let error):
                present(error)
            }
        }
    }

    @MainActor
    private func readImportFile(from url: URL) {
        isBusy = true
        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try BackupTransfer.readEncryptedBackup(from: url))
                } catch {
                    return .failure(error)
                }
            }.value

            isBusy = false
            switch result {
            case .success(let data):
                pendingImportData = data
                importPassword = ""
                showImportPassword = true
            case .failure(let error):
                present(error)
            }
        }
    }

    @MainActor
    private func decryptImportedFile() {
        guard let data = pendingImportData else {
            present(BackupTransferError.invalidDocument)
            return
        }
        do {
            try EncryptedBackupEngine.validatePassword(importPassword)
        } catch {
            present(error)
            return
        }

        let password = importPassword
        importPassword = ""
        showImportPassword = false
        isBusy = true

        Task { @MainActor in
            let result: Result<DecryptedBackup, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try engine.decryptDocument(data, password: password))
                } catch {
                    return .failure(error)
                }
            }.value

            isBusy = false
            switch result {
            case .success(let backup):
                decryptedBackup = backup
                importMode = .merge
            case .failure(let error):
                // EncryptedBackupEngine maps a wrong password and all
                // authenticated tampering to the same public error.
                present(error)
            }
        }
    }

    @MainActor
    private func applyDecryptedBackup() {
        guard let backup = decryptedBackup else { return }
        let snapshot = backup.snapshot
        let mode = importMode
        isBusy = true

        // SwiftData contexts remain on the main actor.  Only the expensive
        // cryptographic work above is detached; this transaction is kept
        // together so save/rollback semantics are explicit.
        do {
            let coordinator = BackupImportCoordinator(context: context, engine: engine)
            _ = try coordinator.importSnapshot(snapshot, mode: mode)
            isBusy = false
            decryptedBackup = nil
            pendingImportData = nil
            dismiss()
        } catch {
            isBusy = false
            present(error)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date,
                                      dateStyle: .medium,
                                      timeStyle: .short)
    }

    @MainActor
    private func present(_ error: Error) {
        errorMessage = safeUserMessage(for: error)
        canRetryImport = pendingImportData != nil && isAuthenticationFailure(error)
        showError = true
    }

    private func clearTransientSecrets() {
        exportPassword = ""
        exportConfirmation = ""
        importPassword = ""
        pendingImportData = nil
        decryptedBackup = nil
        exportDocument = nil
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        guard let error = error as? EncryptedBackupError else { return false }
        return error == .authenticationFailed
    }

    /// Convert all backup-boundary errors to short localizable UI messages.
    /// In particular, wrong passwords and authenticated tampering use exactly
    /// the same string; no underlying CryptoKit, file-system, or persistence
    /// details are shown to the user.
    private func safeUserMessage(for error: Error) -> String {
        if let error = error as? EncryptedBackupError {
            switch error {
            case .authenticationFailed:
                return String(localized: "密码错误或备份文件已损坏,无法解密。")
            case .passwordTooShort:
                return String(localized: "备份密码至少需要 8 个字符。")
            case .passwordConfirmationMismatch:
                return String(localized: "两次输入的备份密码不一致。")
            case .inputTooLarge:
                return String(localized: "备份文件超过 Maren 支持的大小上限。")
            case .unsupportedFormat:
                return String(localized: "这不是受支持的 Maren 备份文件。")
            case .unsupportedSchema:
                return String(localized: "这份备份来自不受支持的版本,请更新 Maren 后重试。")
            case .invalidSnapshot:
                return String(localized: "备份中的记录格式无效,未导入任何数据。")
            case .invalidConfiguration:
                return String(localized: "备份加密配置无效,请更新 Maren 后重试。")
            }
        }
        if let error = error as? BackupTransferError {
            switch error {
            case .invalidDocument:
                return String(localized: "无法读取这份备份文件。")
            case .fileTooLarge:
                return String(localized: "备份文件超过 Maren 支持的大小上限。")
            case .fileReadFailed:
                return String(localized: "无法读取这份备份文件,请重试。")
            }
        }
        if let error = error as? BackupImportCoordinatorError {
            switch error {
            case .invalidMedicationReference:
                return String(localized: "备份中的用药打卡缺少对应的用药记录,未导入任何数据。")
            case .persistenceFailed:
                return String(localized: "备份保存失败,本机原有记录未改动。")
            }
        }
        return String(localized: "备份操作未完成,本机数据未改动。请重试。")
    }
}
