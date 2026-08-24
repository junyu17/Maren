import SwiftUI

struct EducationArticleView: View {
    let item: EducationCatalog.Item
    let isBookmarked: Bool
    let onBookmarkToggle: (Bool) -> Void

    @AppStorage("education.bookmarks") private var bookmarksData = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var currentIsBookmarked: Bool {
        guard !bookmarksData.isEmpty else { return false }
        return Set(bookmarksData.split(separator: ",").map(String.init)).contains(item.id)
    }

    private var localeTitle: String {
        EducationCatalog.localized(item.title)
    }

    private var localeSummary: String {
        EducationCatalog.localized(item.summary)
    }

    private var localeBody: String {
        EducationCatalog.localized(item.body)
    }

    private var localeDisclaimer: String {
        EducationCatalog.localized(item.nonMedicalAdvice)
    }

    private var localeReviewed: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if let date = fmt.date(from: item.reviewedAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.locale = Locale.current
            return display.string(from: date)
        }
        return item.reviewedAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Cover hero
                EducationCover(
                    category: item.category,
                    title: localeTitle,
                    summary: localeSummary,
                    isBookmarked: currentIsBookmarked
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Review date
                HStack {
                    Text(item.category.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(localeReviewed)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // Body
                Text(localeBody)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Sources
                if !item.sources.isEmpty {
                    Divider()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "来源"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(item.sources) { source in
                            if let url = URL(string: source.url), url.scheme == "https" {
                                Link(destination: url) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "safari")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(source.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(source.name), \(source.url)")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Disclaimer
                Divider()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "免责声明"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(localeDisclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onBookmarkToggle(currentIsBookmarked)
                } label: {
                    Image(systemName: currentIsBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentIsBookmarked ? String(localized: "取消收藏") : String(localized: "收藏"))
                .accessibilityAddTraits(currentIsBookmarked ? [] : [])
            }
        }
    }
}
