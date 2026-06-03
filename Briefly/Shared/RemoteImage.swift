import SwiftUI
import ImageIO
import UIKit

enum RemoteImageStyle {
    case hero
    case thumbnail
    case detail
}

// Shared in-memory cache so we can preheat images ahead of swipe/paging.
private enum RemoteImageMemoryCache {
    static let cache = NSCache<NSString, UIImage>()

    static func key(url: URL, targetPixelSize: CGSize) -> NSString {
        "\(url.absoluteString)|\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))" as NSString
    }
}

enum RemoteImagePreheater {
    static var heroTargetPixelSize: CGSize {
        RemoteImage.targetPixelSize(for: .hero)
    }

    static func cachedImage(url: URL, targetPixelSize: CGSize) -> UIImage? {
        RemoteImageMemoryCache.cache.object(forKey: RemoteImageMemoryCache.key(url: url, targetPixelSize: targetPixelSize))
    }

    static func preheat(urls: [URL], targetPixelSize: CGSize, maxConcurrency: Int = 3) async {
        guard !urls.isEmpty else { return }

        let batchSize = max(1, maxConcurrency)
        var startIndex = 0

        while startIndex < urls.count {
            let endIndex = min(startIndex + batchSize, urls.count)
            let batch = Array(urls[startIndex..<endIndex])

            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask {
                        let key = RemoteImageMemoryCache.key(url: url, targetPixelSize: targetPixelSize)
                        if RemoteImageMemoryCache.cache.object(forKey: key) != nil {
                            return
                        }

                        do {
                            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
                            let (data, _) = try await URLSession.shared.data(for: request)
                            let decoded = try await Task.detached(priority: .utility) {
                                try downsampleImage(data: data, targetPixelSize: targetPixelSize)
                            }.value
                            RemoteImageMemoryCache.cache.setObject(decoded, forKey: key)
                        } catch {
                            // Best-effort only; ignore failures.
                        }
                    }
                }
            }

            startIndex = endIndex
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    var style: RemoteImageStyle = .detail

    var body: some View {
        DownsampledRemoteImage(
            url: url,
            targetPixelSize: targetPixelSize,
            placeholder: { placeholder }
        ) { image in
            configured(image: Image(uiImage: image))
        }
        .clipped()
    }

    @ViewBuilder
    private func configured(image: Image) -> some View {
        switch style {
        case .hero:
            // Keep hero rendering lightweight; this view is used inside paged carousels.
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .thumbnail:
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeOut(duration: 0.22)))
        case .detail:
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrieflyTheme.cardLight.opacity(0.35))
                .transition(.opacity.animation(.easeOut(duration: 0.22)))
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [BrieflyTheme.elevatedCard, BrieflyTheme.accent.opacity(0.55), BrieflyTheme.accentBlue.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            Image(systemName: "newspaper.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        )
    }

    private var targetPixelSize: CGSize {
        Self.targetPixelSize(for: style)
    }

    static func targetPixelSize(for style: RemoteImageStyle) -> CGSize {
        let scale = UIScreen.main.scale
        switch style {
        case .hero:
            return CGSize(width: 900 * scale, height: 506 * scale) // ~16:9
        case .thumbnail:
            return CGSize(width: 220 * scale, height: 124 * scale) // slightly larger than 92x52 to keep it crisp
        case .detail:
            return CGSize(width: 1200 * scale, height: 675 * scale)
        }
    }
}

private struct DownsampledRemoteImage<Placeholder: View>: View {
    let url: URL?
    let targetPixelSize: CGSize
    let placeholder: () -> Placeholder
    let content: (UIImage) -> AnyView

    init(
        url: URL?,
        targetPixelSize: CGSize,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping (UIImage) -> some View
    ) {
        self.url = url
        self.targetPixelSize = targetPixelSize
        self.placeholder = placeholder
        self.content = { AnyView(content($0)) }
    }

    @StateObject private var loader = DownsampledImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: taskKey) {
            await loader.load(url: url, targetPixelSize: targetPixelSize)
        }
    }

    private var taskKey: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)|\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))"
    }
}

@MainActor
private final class DownsampledImageLoader: ObservableObject {
    @Published var image: UIImage?

    func load(url: URL?, targetPixelSize: CGSize) async {
        guard let url else {
            image = nil
            return
        }

        let key = RemoteImageMemoryCache.key(url: url, targetPixelSize: targetPixelSize)
        if let cached = RemoteImageMemoryCache.cache.object(forKey: key) {
            image = cached
            return
        }

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try await Task.detached(priority: .utility) {
                try downsampleImage(data: data, targetPixelSize: targetPixelSize)
            }.value

            RemoteImageMemoryCache.cache.setObject(decoded, forKey: key)
            image = decoded
        } catch {
            image = nil
        }
    }
}

private func downsampleImage(data: Data, targetPixelSize: CGSize) throws -> UIImage {
    let maxDimension = max(targetPixelSize.width, targetPixelSize.height)
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false
    ]

    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
        throw NSError(domain: "BrieflyImage", code: 1)
    }

    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
        throw NSError(domain: "BrieflyImage", code: 2)
    }

    return UIImage(cgImage: cgImage)
}
