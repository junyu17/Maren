import SwiftUI
import SwiftData

/// 层级 2 · 自定义追踪项管理(增删)。新增在「今天」页的症状区就地进行,这里主要负责删除/查看。
struct CustomSymptomManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomSymptom.createdAt) private var items: [CustomSymptom]
    @State private var showAdd = false
    @State private var showPaywall = false
    @ObservedObject private var store = Store.shared

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    Text("你还没有自定义追踪项。可以在「今天」页的症状区点「＋ 自定义」添加,也可以点右上角「＋」。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack {
                        Text(item.emoji)
                        Text(item.label)
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                if !store.premium {
                    Text("免费最多 \(CustomSymptom.freeLimit) 个自定义项,Pro 无限。已达上限时点「＋」升级。")
                }
            }
        }
        .navigationTitle("自定义追踪项")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tryAdd() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加自定义追踪项")
            }
        }
        .sheet(isPresented: $showAdd) {
            CustomSymptomEditor { label, emoji in
                context.insert(CustomSymptom(label: label, emoji: emoji))
                try? context.save()
                CustomSymptomStore.refresh(context)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
        CustomSymptomStore.refresh(context)
    }

    /// 添加:免费层达上限弹付费墙,Pro 无限。
    private func tryAdd() {
        if !store.premium && items.count >= CustomSymptom.freeLimit {
            showPaywall = true
        } else {
            showAdd = true
        }
    }
}
