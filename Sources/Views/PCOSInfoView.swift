import SwiftUI

/// 层级 2 · PCOS 专项科普(立项书 V2 点名的细分人群)。
/// 面向不规律 / 长周期用户,强调 Maren 对她们友好,并给出可追踪项建议。非医疗建议。
struct PCOSInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(icon: "heart.text.square",
                            title: String(localized: "为不规律的周期而生"),
                            body: String(localized: "如果你有 PCOS 或周期本来就不规律,很多主流 app 的「第 14 天排卵」假设会让预测很不准。Maren 只学习你自己的真实记录,支持 15–120 天的长周期,并如实呈现波动范围,而不是假装精准。"))

                    section(icon: "list.bullet.clipboard",
                            title: String(localized: "PCOS 值得追踪什么"),
                            body: String(localized: "除了经期和情绪,你可以留意:体重变化、痤疮、多毛、脱发、疲惫、食欲与情绪波动。在「今天」页记录体重,并用症状标签或「自定义追踪项」记下这些,时间久了能看到自己的规律。"))

                    section(icon: "pills",
                            title: String(localized: "把用药也记下来"),
                            body: String(localized: "如果在服用二甲双胍、肌醇或其他补剂,可以在「设置 · 用药与补剂」里添加并开启每日提醒,方便坚持和复盘。"))

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                        Text("以上为一般性健康科普,不构成医学诊断或治疗建议。PCOS 的诊断与管理请咨询专业医生。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("关于 PCOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func section(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            Text(body).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
