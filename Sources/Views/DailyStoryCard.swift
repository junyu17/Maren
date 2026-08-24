import SwiftUI

// MARK: - EducationCover (reusable hero for education content)

struct EducationCover: View {
    let category: EducationCatalog.Category
    let title: String
    let summary: String
    let isBookmarked: Bool
    var readingCue: String? = nil
    var compact: Bool = false

    private var categoryIcon: String {
        switch category {
        case .general:          return "book.closed"
        case .menstrualHealth:  return "drop.fill"
        case .cyclePhases:      return "arrow.triangle.2.circlepath"
        case .perimenopause:    return "sparkles"
        case .nutrition:        return "leaf.fill"
        case .exercise:         return "figure.run"
        case .mentalWellbeing:  return "heart.fill"
        }
    }

    private var categoryColors: [Color] {
        switch category {
        case .general:          return [Color(red: 0.18, green: 0.22, blue: 0.45), Color(red: 0.12, green: 0.25, blue: 0.48)]
        case .menstrualHealth:  return [Color(red: 0.48, green: 0.22, blue: 0.30), Color(red: 0.42, green: 0.25, blue: 0.38)]
        case .cyclePhases:      return [Color(red: 0.28, green: 0.18, blue: 0.42), Color(red: 0.35, green: 0.20, blue: 0.48)]
        case .perimenopause:    return [Color(red: 0.52, green: 0.30, blue: 0.22), Color(red: 0.48, green: 0.35, blue: 0.28)]
        case .nutrition:        return [Color(red: 0.16, green: 0.35, blue: 0.22), Color(red: 0.22, green: 0.40, blue: 0.30)]
        case .exercise:         return [Color(red: 0.12, green: 0.22, blue: 0.40), Color(red: 0.18, green: 0.28, blue: 0.45)]
        case .mentalWellbeing:  return [Color(red: 0.14, green: 0.35, blue: 0.38), Color(red: 0.18, green: 0.40, blue: 0.42)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.white)
                    .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
                    .background(
                        LinearGradient(colors: categoryColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))

                Text(category.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(isBookmarked ? .white : .white.opacity(0.6))
                    .accessibilityLabel(isBookmarked ? String(localized: "已收藏") : String(localized: "未收藏"))
            }

            Text(title)
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.isEmpty {
                Text(summary)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let cue = readingCue {
                HStack(spacing: 4) {
                    Text(cue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(compact ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: categoryColors.map { $0.opacity(0.85) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.label), \(title), \(summary)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - DailyStoryCard

struct DailyStoryCard: View {
    let item: EducationCatalog.Item
    let isBookmarked: Bool

    init(item: EducationCatalog.Item, isBookmarked: Bool = false) {
        self.item = item
        self.isBookmarked = isBookmarked
    }

    private var localeTitle: String {
        EducationCatalog.localized(item.title)
    }

    private var localeSummary: String {
        EducationCatalog.localized(item.summary)
    }

    var body: some View {
        EducationCover(
            category: item.category,
            title: localeTitle,
            summary: localeSummary,
            isBookmarked: isBookmarked,
            readingCue: String(localized: "阅读全文"),
            compact: true
        )
    }
}
