import Foundation

enum NativeAdPlacement: String, Hashable {
    case home
    case category
    case articleDetail
    case sports
    case jobs
    case books
}

struct NativeAdSlot: Identifiable, Hashable {
    let id: String
    let placement: NativeAdPlacement
}

enum ArticleFeedItem: Identifiable {
    case article(Article)
    case nativeAd(NativeAdSlot)

    var id: String {
        switch self {
        case .article(let article):
            return "article-\(article.id)"
        case .nativeAd(let slot):
            return "native-ad-\(slot.id)"
        }
    }
}

enum NativeAdInserter {
    static func articleItems(
        from articles: [Article],
        placement: NativeAdPlacement,
        interval: Int,
        minimumContentBeforeFirstAd: Int
    ) -> [ArticleFeedItem] {
        guard interval > 0, minimumContentBeforeFirstAd > 0 else {
            return articles.map(ArticleFeedItem.article)
        }

        var items: [ArticleFeedItem] = []

        for (index, article) in articles.enumerated() {
            items.append(.article(article))

            let contentCount = index + 1
            let hasMoreContent = contentCount < articles.count
            let shouldInsertAd = contentCount >= minimumContentBeforeFirstAd &&
                contentCount.isMultiple(of: interval) &&
                hasMoreContent

            if shouldInsertAd {
                items.append(
                    .nativeAd(
                        NativeAdSlot(
                            id: "\(placement.rawValue)-after-\(contentCount)",
                            placement: placement
                        )
                    )
                )
            }
        }

        return items
    }
}
