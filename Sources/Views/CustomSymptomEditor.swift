import SwiftUI

/// 层级 2 · 新建自定义症状/追踪标签。极简:一个 emoji + 一个名称。
struct CustomSymptomEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (_ label: String, _ emoji: String) -> Void

    @State private var label = ""
    @State private var emoji = "📝"

    /// 常用 emoji 备选,免得用户去调系统 emoji 键盘。
    private let choices = ["📝", "🩸", "🤕", "😴", "🔥", "💊", "🍫", "😰", "🌡️", "💪", "🧘‍♀️", "🥗", "☕️", "💧", "🤢", "😵‍💫"]
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如:偏头痛、拉伸、喝水", text: $label)
                }
                Section("图标") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(choices, id: \.self) { e in
                            Text(e)
                                .font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(emoji == e ? FlowLevel.spotting.tint.opacity(0.3) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { emoji = e }
                                .accessibilityLabel(Text(e))
                                .accessibilityAddTraits(emoji == e ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("自定义追踪项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, emoji)
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
