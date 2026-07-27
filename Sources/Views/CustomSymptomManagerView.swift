import SwiftUI
import SwiftData

/// 层级 2 · 自定义追踪项管理(增删)。新增在「今天」页的症状区就地进行,这里主要负责删除/查看。
struct CustomSymptomManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomSymptom.createdAt) private var items: [CustomSymptom]
    @State private var showAdd = false

    var body: some View {
        List {
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
        }
        .navigationTitle("自定义追踪项")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
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
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
        CustomSymptomStore.refresh(context)
    }
}
