import SwiftUI

struct StoryReaderView: View {
    let item: EducationCatalog.Item
    let isBookmarked: Bool
    let onBookmarkToggle: (Bool) -> Void

    init(item: EducationCatalog.Item, isBookmarked: Bool, onBookmarkToggle: @escaping (Bool) -> Void) {
        self.item = item
        self.isBookmarked = isBookmarked
        self.onBookmarkToggle = onBookmarkToggle
    }

    var body: some View {
        EducationArticleView(item: item, isBookmarked: isBookmarked, onBookmarkToggle: onBookmarkToggle)
    }
}
