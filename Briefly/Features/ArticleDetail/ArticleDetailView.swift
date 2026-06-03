import SafariServices
import SwiftUI
import UIKit

struct ArticleDetailView: View {
    let article: Article
    let isSaved: Bool
    let onToggleSave: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var cardIndex = 0
    @State private var showBrowser = false
    @State private var showChat = false
    @State private var showShareSheet = false
    @State private var showAuth = false

    private var summaryPagerHeight: CGFloat {
        let longestCard = article.summaryCards.map(\.count).max() ?? 0
        if longestCard > 220 { return 190 }
        if longestCard > 140 { return 160 }
        return 132
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    topBar

                    Text(article.headline)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                        .lineLimit(4)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    RemoteImage(url: article.imageURL, style: .detail)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    TabView(selection: $cardIndex) {
                        ForEach(Array(article.summaryCards.enumerated()), id: \.offset) { index, card in
                            SummaryCard(text: card).tag(index)
                        }
                    }
                    .frame(height: summaryPagerHeight)
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    if article.summaryCards.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<article.summaryCards.count, id: \.self) { index in
                                Circle()
                                    .fill(index == cardIndex ? BrieflyTheme.text(colorScheme) : BrieflyTheme.text(colorScheme).opacity(0.16))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, -2)
                    }

                    NativeAdCard(
                        slot: NativeAdSlot(
                            id: "article-detail-\(article.id)",
                            placement: .articleDetail
                        )
                    )
                    .padding(.top, 6)

                    Color.clear.frame(height: 74)
                }
                .padding(20)
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        BrieflyTheme.background(colorScheme).opacity(0),
                        BrieflyTheme.background(colorScheme).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)

                Button {
                    showChat = true
                } label: {
                    Text("Ask Briefly")
                        .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(BrieflyTheme.actionGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(articleBackground)
        .ignoresSafeArea()
        .sheet(isPresented: $showBrowser) {
            if let url = article.originalURL {
                SafariSheet(url: url)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showChat) {
            AskBrieflyView(article: article)
        }
        .sheet(isPresented: $showAuth) {
            AuthView()
                .environmentObject(appState)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            CircleIconButton(systemName: "chevron.left") {
                dismiss()
            }

            Spacer()

            CircleIconButton(systemName: "link") {
                showBrowser = true
            }
            CircleIconButton(systemName: isSaved ? "bookmark.fill" : "bookmark") {
                if appState.session == nil {
                    Haptics.selection()
                    showAuth = true
                } else {
                    Task { await onToggleSave() }
                }
            }
            CircleIconButton(systemName: "square.and.arrow.up") {
                showShareSheet = true
            }
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = [article.headline]
        if let originalURL = article.originalURL {
            items.append(originalURL)
        }
        return items
    }

    private var articleBackground: some View {
        ZStack {
            BrieflyTheme.background(colorScheme)
            RadialGradient(
                colors: [BrieflyTheme.glowViolet, .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 360
            )
        }
    }
}

private struct SummaryCard: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
