import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedArticle: Article?
    @State private var featureIndex = 0
    @State private var isSearchVisible = false
    @State private var isShowingAll = false
    @State private var isShowingGeneralChat = false
    @State private var isShowingExplainLink = false
    @State private var isShowingAuth = false
    @State private var selectedMarketSnapshot: MarketSnapshot?
    private let carouselTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()
    private let refreshHeartbeat = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 30) {
                        header
                        if isSearchVisible {
                            searchBar
                        }
                        if !viewModel.availableCategories.isEmpty {
                            categoryChips
                        }
                        if viewModel.isLoading && viewModel.allArticles.isEmpty {
                            loadingState
                        } else if isSearching {
                            searchResultsSection
                        } else {
                            dailyBriefSection
                            NativeAdCard(
                                slot: NativeAdSlot(
                                    id: "home-after-daily-brief",
                                    placement: .home
                                )
                            )
                            marketSection
                            cryptoSection
                            liveNowSection
                            featuredCarousel
                            picksSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await viewModel.load(session: appState.session, force: true, desiredCount: 48)
                }
                .background(BrieflyTheme.background(colorScheme))
                .navigationBarHidden(true)
                .sheet(item: $selectedArticle) { article in
                    ArticleDetailView(article: article, isSaved: viewModel.savedIDs.contains(article.id)) {
                        await viewModel.toggleSave(article: article, session: appState.session)
                    }
                }
                .sheet(isPresented: $isShowingGeneralChat) {
                    AskBrieflyView(newsContext: generalNewsContext)
                }
                .sheet(isPresented: $isShowingExplainLink) {
                    ExplainLinkView()
                }
                .sheet(isPresented: $isShowingAuth) {
                    AuthView()
                        .environmentObject(appState)
                }
                .fullScreenCover(item: $selectedMarketSnapshot) { snapshot in
                    MarketDetailView(snapshot: snapshot)
                }
                .navigationDestination(isPresented: $isShowingAll) {
                    AllArticlesView(
                        viewModel: viewModel,
                        selectedArticle: $selectedArticle,
                        isShowingAuth: $isShowingAuth,
                        session: appState.session
                    )
                }
                .task {
                    await viewModel.load(session: appState.session, desiredCount: 48)
                }
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.handleSearchTextChange()
                }
                .onReceive(carouselTimer) { _ in
                    // Disabled: auto-advancing a paged carousel while the user is scrolling is a major jank source.
                    // We can reintroduce this later with interaction-aware pausing, but stability first.
                }
                .onReceive(refreshHeartbeat) { _ in
                    Task {
                        await viewModel.handleHeartbeat(session: appState.session)
                    }
                }
                .preferredColorScheme(theme.colorScheme)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HomeLogoLockup()

            Spacer(minLength: 16)

            CircleIconButton(systemName: isSearchVisible ? "xmark" : "magnifyingglass") {
                withAnimation {
                    isSearchVisible.toggle()
                }
            }

            CircleIconButton(systemName: "sparkle", tint: BrieflyTheme.accent, isProminent: true) {
                isShowingGeneralChat = true
            }

            CircleIconButton(systemName: "link") {
                isShowingExplainLink = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.45))

            TextField("Search stories", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .tint(BrieflyTheme.accent)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.text(colorScheme).opacity(0.12), lineWidth: 1)
        }
        .shadow(color: BrieflyTheme.text(colorScheme).opacity(0.08), radius: 16, y: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Results")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    Text(resultsSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.6))
                }

                Spacer()
            }

            cryptoSearchResultsSection

            if let answer = viewModel.searchFallbackAnswer, let query = viewModel.searchFallbackQuery {
                AIFallbackSearchCard(query: query, answer: answer)
            } else if viewModel.searchMatchedArticles.isEmpty && !viewModel.hasCryptoSearchResults {
                EmptyPicksState(hasSearchText: true)
            } else {
                ForEach(categoryFeedItems(from: viewModel.searchMatchedArticles)) { item in
                    feedRow(for: item)
                }
            }
        }
    }

    private var cryptoSearchResultsSection: some View {
        Group {
            if viewModel.hasCryptoSearchResults {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Crypto Assets")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    ForEach(viewModel.cryptoSearchSnapshots.prefix(6)) { snapshot in
                        Button {
                            Haptics.selection()
                            selectedMarketSnapshot = snapshot
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(snapshot.ticker)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.green)

                                        if let rank = snapshot.rank {
                                            Text("#\(Int(rank))")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.46))
                                        }
                                    }

                                    Text(snapshot.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.72))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 10)

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(snapshot.priceText)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                                    Text(snapshot.changeText)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(snapshot.isPositive ? Color.green : Color.red)
                                        .lineLimit(1)
                                }
                            }
                            .padding(14)
                            .background(BrieflyTheme.card(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let message = viewModel.cryptoSearchStatusMessage,
                      viewModel.searchMatchedArticles.isEmpty {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.5))
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(viewModel.availableCategories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleCategory(category)
                        }
                    } label: {
                        Text(category.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(viewModel.activeCategories.contains(category) ? Color.white : BrieflyTheme.text(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(viewModel.activeCategories.contains(category) ? BrieflyTheme.actionFill : BrieflyTheme.card(colorScheme))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var featuredCarousel: some View {
        VStack(spacing: 12) {
            if viewModel.featuredArticles.isEmpty {
                FeaturedPlaceholderCard()
                    .frame(height: 170)
            } else {
                FeaturedCarouselPager(
                    articles: viewModel.featuredArticles,
                    featureIndex: $featureIndex,
                    onSelect: { article in
                        Haptics.selection()
                        selectedArticle = article
                    }
                )
                .frame(height: 170)
            }

            HStack(spacing: 8) {
                ForEach(0..<max(viewModel.featuredArticles.count, 1), id: \.self) { index in
                    Capsule()
                        .fill(index == featureIndex ? BrieflyTheme.text(colorScheme) : BrieflyTheme.text(colorScheme).opacity(0.16))
                        .frame(width: index == featureIndex ? 16 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: featureIndex)
                }
            }
        }
    }

    private var liveNowSection: some View {
        Group {
            if !viewModel.liveNowArticles.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Live Now")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        Spacer()

                        if let lastUpdatedAt = viewModel.lastUpdatedAt {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                LiveTimestampText(date: lastUpdatedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.6))
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(viewModel.liveNowArticles) { article in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(article.category)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(BrieflyTheme.accent)

                                    Text(article.headline)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                                        .lineLimit(3)

                                    if let publishedAt = article.publishedAt {
                                        LiveTimestampText(date: publishedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.58))
                                    }
                                }
                                .frame(width: 220, alignment: .leading)
                                .padding(16)
                                .background(BrieflyTheme.card(colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .onTapGesture {
                                    selectedArticle = article
                                }
                            }
                        }
                    }

                }
            }
        }
    }

    private var marketSection: some View {
        Group {
            if !viewModel.marketSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Market")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        Spacer()
                    }

                    if let marketUpdatedAt = viewModel.marketUpdatedAt {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 7, height: 7)
                            LiveTimestampText(date: marketUpdatedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.6))
                        }
                    }

                    if let message = viewModel.marketStatusMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(viewModel.marketSnapshots) { snapshot in
                                marketCard(snapshot)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
            }
        }
    }

    private var cryptoSection: some View {
        Group {
            if !viewModel.cryptoSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Crypto")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        Spacer()
                    }

                    if let cryptoUpdatedAt = viewModel.cryptoUpdatedAt {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            LiveTimestampText(date: cryptoUpdatedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.6))
                        }
                    }

                    if let message = viewModel.cryptoStatusMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    }

                    cryptoStatsStrip

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(viewModel.cryptoSnapshots) { snapshot in
                                cryptoCard(snapshot)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)

                    trendingCryptoRow
                    cryptoMoversRow
                }
            }
        }
    }

    private var cryptoStatsStrip: some View {
        Group {
            if let stats = viewModel.cryptoStats {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        cryptoStatPill("Market Cap", compactMarketNumber(stats.totalMarketCap ?? 0))
                        cryptoStatPill("24h Volume", compactMarketNumber(stats.totalVolume24h ?? 0))
                        if let dominance = stats.btcDominance {
                            cryptoStatPill("BTC Dom.", String(format: "%.1f%%", dominance))
                        }
                        if let coins = stats.totalCoins {
                            cryptoStatPill("Coins", String(format: "%.0f", coins))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            } else if let message = viewModel.cryptoStatsStatusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.5))
            }
        }
    }

    private func marketCard(_ snapshot: MarketSnapshot) -> some View {
        Button {
            Haptics.selection()
            selectedMarketSnapshot = snapshot
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(snapshot.ticker)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrieflyTheme.accent)
                    .lineLimit(1)

                Text(snapshot.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(snapshot.priceText)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(snapshot.changeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(snapshot.isPositive ? Color.green : Color.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let updatedAt = snapshot.updatedAt {
                    LiveTimestampText(date: updatedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.58))
                        .lineLimit(1)
                }
            }
            .frame(width: 128, alignment: .leading)
            .frame(minHeight: 128, alignment: .leading)
            .padding(14)
            .background(BrieflyTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cryptoCard(_ snapshot: MarketSnapshot) -> some View {
        Button {
            Haptics.selection()
            selectedMarketSnapshot = snapshot
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(snapshot.ticker)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)

                    Spacer()

                    if let rank = snapshot.rank {
                        Text("#\(Int(rank))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.52))
                    }
                }

                Text(snapshot.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(snapshot.priceText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(snapshot.changeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(snapshot.isPositive ? Color.green : Color.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let marketCap = snapshot.marketCap {
                    Text("Cap \(compactMarketNumber(marketCap))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
                        .lineLimit(1)
                }
            }
            .frame(width: 134, alignment: .leading)
            .frame(minHeight: 144, alignment: .leading)
            .padding(14)
            .background(BrieflyTheme.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cryptoStatPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.56))

            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
        }
        .frame(width: 124, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var trendingCryptoRow: some View {
        Group {
            if !viewModel.trendingCryptoSnapshots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trending")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(viewModel.trendingCryptoSnapshots) { snapshot in
                                Button {
                                    Haptics.selection()
                                    selectedMarketSnapshot = snapshot
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(snapshot.ticker)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Color.green)

                                            Text(snapshot.name)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.72))
                                                .lineLimit(1)
                                        }

                                        Text(snapshot.changeText)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(snapshot.isPositive ? Color.green : Color.red)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 132, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(BrieflyTheme.elevatedCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
            } else if let message = viewModel.trendingCryptoStatusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.5))
            }
        }
    }

    private var cryptoMoversRow: some View {
        Group {
            if !viewModel.cryptoGainers.isEmpty || !viewModel.cryptoLosers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gainers / Losers")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    HStack(alignment: .top, spacing: 12) {
                        cryptoMoverColumn(title: "Gainers", snapshots: viewModel.cryptoGainers, tint: .green)
                        cryptoMoverColumn(title: "Losers", snapshots: viewModel.cryptoLosers, tint: .red)
                    }
                }
            } else if let message = viewModel.cryptoMoversStatusMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.5))
            }
        }
    }

    private func cryptoMoverColumn(title: String, snapshots: [MarketSnapshot], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)

            ForEach(snapshots.prefix(4)) { snapshot in
                Button {
                    Haptics.selection()
                    selectedMarketSnapshot = snapshot
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.ticker)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(BrieflyTheme.text(colorScheme))
                                .lineLimit(1)

                            Text(snapshot.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.54))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Text(snapshot.changePercent.map { String(format: "%+.1f%%", $0) } ?? snapshot.changeText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(snapshot.isPositive ? Color.green : Color.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(BrieflyTheme.elevatedCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var dailyBriefSection: some View {
        let articles = viewModel.dailyBriefArticles
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("Today in 60 Seconds")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    Spacer()

                    Text("\(articles.count) essentials")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BrieflyTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BrieflyTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(articles.isEmpty ? BrieflyTheme.accent : BrieflyTheme.accentBlue)
                        .frame(width: 8, height: 8)

                    if let lastUpdatedAt = viewModel.lastUpdatedAt {
                        Text("Brief refreshed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))

                        LiveTimestampText(date: lastUpdatedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.62))
                    } else {
                        Text("Building today's brief")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    }
                }
            }

            if articles.isEmpty {
                BriefEmptyCard()
            } else {
                VStack(spacing: 0) {
                    if let lead = articles.first {
                        Button {
                            selectedArticle = lead
                        } label: {
                            BriefLeadStory(article: lead)
                        }
                        .buttonStyle(.plain)
                    }

                    let rest = Array(articles.dropFirst())
                    if !rest.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(rest.enumerated()), id: \.element.id) { index, article in
                                Divider()
                                    .overlay(BrieflyTheme.text(colorScheme).opacity(0.08))

                                Button {
                                    selectedArticle = article
                                } label: {
                                    BriefDigestRow(index: index + 2, article: article)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .background(
                    LinearGradient(
                        colors: [
                            BrieflyTheme.card(colorScheme),
                            BrieflyTheme.card(colorScheme).opacity(colorScheme == .dark ? 0.78 : 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(BrieflyTheme.text(colorScheme).opacity(0.08), lineWidth: 1)
                }
            }
        }
    }

    private var picksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's Picks")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                Spacer()
                Button("View All") {
                        isShowingAll = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
            }

            if let answer = viewModel.searchFallbackAnswer, let query = viewModel.searchFallbackQuery {
                AIFallbackSearchCard(query: query, answer: answer)
            } else if viewModel.filteredPicks.isEmpty {
                EmptyPicksState(hasSearchText: !viewModel.searchText.isEmpty)
            } else {
                ForEach(homeFeedItems(from: viewModel.filteredPicks)) { item in
                    feedRow(for: item)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            FeaturedPlaceholderCard()
                .frame(height: 170)

            ForEach(0..<4, id: \.self) { _ in
                ArticleRowPlaceholder()
            }
        }
    }

    private func bookmarkTitle(for article: Article, session: UserSession?) -> String {
        guard session != nil else { return "Sign In to Save" }
        return viewModel.savedIDs.contains(article.id) ? "Remove Bookmark" : "Save"
    }

    private func handleBookmark(_ article: Article) {
        guard appState.session != nil else {
            Haptics.selection()
            isShowingAuth = true
            return
        }

        Task {
            Haptics.impact(.light)
            await viewModel.toggleSave(article: article, session: appState.session)
        }
    }

    private func homeFeedItems(from articles: [Article]) -> [ArticleFeedItem] {
        NativeAdInserter.articleItems(
            from: articles,
            placement: viewModel.activeCategories.isEmpty ? .home : .category,
            interval: viewModel.activeCategories.isEmpty ? 6 : 5,
            minimumContentBeforeFirstAd: viewModel.activeCategories.isEmpty ? 6 : 5
        )
    }

    private func categoryFeedItems(from articles: [Article]) -> [ArticleFeedItem] {
        NativeAdInserter.articleItems(
            from: articles,
            placement: .category,
            interval: 5,
            minimumContentBeforeFirstAd: 5
        )
    }

    @ViewBuilder
    private func feedRow(for item: ArticleFeedItem) -> some View {
        switch item {
        case .article(let article):
            Button {
                selectedArticle = article
            } label: {
                ArticleRow(article: article, isSaved: viewModel.savedIDs.contains(article.id))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(bookmarkTitle(for: article, session: appState.session)) {
                    handleBookmark(article)
                }
            }
        case .nativeAd(let slot):
            NativeAdCard(slot: slot)
        }
    }
}

private struct HomeLogoLockup: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("BrieflyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .blendMode(.screen)
                .shadow(color: BrieflyTheme.accent.opacity(0.50), radius: 12, x: 0, y: 0)
                .shadow(color: BrieflyTheme.accentBlue.opacity(0.24), radius: 18, x: 0, y: 0)

            Text("Briefly")
                .font(.custom("Yeager-Light", size: 34))
                .tracking(0.35)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            BrieflyTheme.primaryText.opacity(0.90),
                            BrieflyTheme.secondaryText.opacity(0.94)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: BrieflyTheme.accent.opacity(0.10), radius: 6, x: 0, y: 0)
                .baselineOffset(-0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Briefly")
    }
}

private struct FeaturedCarouselPager: View {
    let articles: [Article]
    @Binding var featureIndex: Int
    let onSelect: (Article) -> Void

    @State private var isPreheated = false
    @State private var cachedImages: [String: UIImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width

            Group {
                if isPreheated {
                    UIKitFeaturedCarousel(
                        articles: articles,
                        images: cachedImages,
                        currentIndex: $featureIndex,
                        onSelect: onSelect
                    )
                } else {
                    FeaturedPlaceholderCard()
                        .frame(width: pageWidth, height: 170)
                }
            }
        }
        .task(id: preheatKey) {
            isPreheated = false
            cachedImages = [:]

            // Preheat a handful of hero images so paging never triggers a fresh decode mid-swipe.
            let urls = articles.compactMap(\.imageURL)
            let target = RemoteImagePreheater.heroTargetPixelSize
            await RemoteImagePreheater.preheat(urls: Array(urls.prefix(6)), targetPixelSize: target, maxConcurrency: 2)

            var warmedImages: [String: UIImage] = [:]
            for url in urls.prefix(6) {
                if let image = RemoteImagePreheater.cachedImage(url: url, targetPixelSize: target) {
                    warmedImages[url.absoluteString] = image
                }
            }

            // Flip the UI only after the cache is warm.
            await MainActor.run {
                cachedImages = warmedImages
                featureIndex = clampIndex(featureIndex)
                isPreheated = true
            }
        }
    }

    private func clampIndex(_ index: Int) -> Int {
        guard !articles.isEmpty else { return 0 }
        return min(max(index, 0), articles.count - 1)
    }

    private var preheatKey: String {
        articles.prefix(6).compactMap(\.imageURL?.absoluteString).joined(separator: "|")
    }
}

private struct UIKitFeaturedCarousel: UIViewRepresentable {
    let articles: [Article]
    let images: [String: UIImage]
    @Binding var currentIndex: Int
    let onSelect: (Article) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(currentIndex: $currentIndex, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> FeaturedCarouselHostView {
        FeaturedCarouselHostView()
    }

    func updateUIView(_ uiView: FeaturedCarouselHostView, context: Context) {
        context.coordinator.currentIndex = $currentIndex
        context.coordinator.onSelect = onSelect

        uiView.configure(
            articles: articles,
            images: images,
            selectedIndex: currentIndex,
            onIndexChange: { [weak coordinator = context.coordinator] index in
                coordinator?.updateIndex(index)
            },
            onSelect: { [weak coordinator = context.coordinator] article in
                coordinator?.select(article)
            }
        )
    }

    final class Coordinator {
        var currentIndex: Binding<Int>
        var onSelect: (Article) -> Void

        init(currentIndex: Binding<Int>, onSelect: @escaping (Article) -> Void) {
            self.currentIndex = currentIndex
            self.onSelect = onSelect
        }

        func updateIndex(_ index: Int) {
            if currentIndex.wrappedValue != index {
                currentIndex.wrappedValue = index
            }
        }

        func select(_ article: Article) {
            onSelect(article)
        }
    }
}

private final class FeaturedCarouselHostView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var pageViews: [FeaturedCarouselPageView] = []
    private var articles: [Article] = []
    private var images: [String: UIImage] = [:]
    private var articleIDs: [String] = []
    private var imageKeys: Set<String> = []
    private var selectedIndex = 0
    private var onIndexChange: ((Int) -> Void)?
    private var onSelect: ((Article) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(
        articles: [Article],
        images: [String: UIImage],
        selectedIndex: Int,
        onIndexChange: @escaping (Int) -> Void,
        onSelect: @escaping (Article) -> Void
    ) {
        let newArticleIDs = articles.map(\.id)
        let newImageKeys = Set(images.keys)
        let shouldRebuild = newArticleIDs != articleIDs || newImageKeys != imageKeys

        self.articles = articles
        self.images = images
        self.articleIDs = newArticleIDs
        self.imageKeys = newImageKeys
        self.selectedIndex = clamp(selectedIndex)
        self.onIndexChange = onIndexChange
        self.onSelect = onSelect

        if shouldRebuild {
            rebuildPages()
        } else {
            updatePages()
        }

        setNeedsLayout()
        applySelectedOffsetIfIdle(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        scrollView.frame = bounds

        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        for (index, pageView) in pageViews.enumerated() {
            pageView.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }

        scrollView.contentSize = CGSize(width: width * CGFloat(pageViews.count), height: height)
        applySelectedOffsetIfIdle(animated: false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        commitCurrentPage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            commitCurrentPage()
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        commitCurrentPage()
    }

    private func setup() {
        clipsToBounds = false

        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = false
        addSubview(scrollView)
    }

    private func rebuildPages() {
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = articles.enumerated().map { index, article in
            let pageView = FeaturedCarouselPageView()
            pageView.configure(article: article, image: image(for: article))
            pageView.addAction(
                UIAction { [weak self] _ in
                    self?.selectArticle(at: index)
                },
                for: .touchUpInside
            )
            scrollView.addSubview(pageView)
            return pageView
        }
    }

    private func updatePages() {
        for (index, pageView) in pageViews.enumerated() where articles.indices.contains(index) {
            pageView.configure(article: articles[index], image: image(for: articles[index]))
        }
    }

    private func selectArticle(at index: Int) {
        guard articles.indices.contains(index) else { return }
        onSelect?(articles[index])
    }

    private func commitCurrentPage() {
        guard bounds.width > 0 else { return }
        let rawIndex = Int(round(scrollView.contentOffset.x / bounds.width))
        selectedIndex = clamp(rawIndex)
        onIndexChange?(selectedIndex)
    }

    private func applySelectedOffsetIfIdle(animated: Bool) {
        guard bounds.width > 0 else { return }
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else { return }

        let targetX = CGFloat(selectedIndex) * bounds.width
        if abs(scrollView.contentOffset.x - targetX) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: animated)
        }
    }

    private func image(for article: Article) -> UIImage? {
        guard let key = article.imageURL?.absoluteString else { return nil }
        return images[key]
    }

    private func clamp(_ index: Int) -> Int {
        guard !articles.isEmpty else { return 0 }
        return min(max(index, 0), articles.count - 1)
    }
}

private final class FeaturedCarouselPageView: UIControl {
    private let imageView = UIImageView()
    private let fallbackGradient = CAGradientLayer()
    private let scrimLayer = CAGradientLayer()
    private let categoryLabel = UILabel()
    private let headlineLabel = UILabel()
    private let sourceLabel = UILabel()
    private let timestampLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(article: Article, image: UIImage?) {
        imageView.image = image
        categoryLabel.text = article.category.uppercased()
        headlineLabel.text = article.headline
        sourceLabel.text = article.source
        timestampLabel.text = article.publishedAt?.relativeBrieflyTimestamp
        timestampLabel.isHidden = article.publishedAt == nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        fallbackGradient.frame = bounds
        imageView.frame = bounds
        scrimLayer.frame = bounds

        let padding: CGFloat = 14
        let labelWidth = bounds.width - (padding * 2)
        let bottom = bounds.height - padding

        categoryLabel.frame = CGRect(x: padding, y: bottom - 84, width: labelWidth, height: 14)
        headlineLabel.frame = CGRect(x: padding, y: bottom - 63, width: labelWidth, height: 44)

        let metaY = bottom - 12
        if timestampLabel.isHidden {
            sourceLabel.frame = CGRect(x: padding, y: metaY, width: labelWidth, height: 14)
        } else {
            timestampLabel.frame = CGRect(x: bounds.width - padding - 82, y: metaY, width: 82, height: 14)
            sourceLabel.frame = CGRect(x: padding, y: metaY, width: labelWidth - 92, height: 14)
        }
    }

    private func setup() {
        isExclusiveTouch = true
        backgroundColor = UIColor(red: 1.0, green: 0.59, blue: 0.34, alpha: 1)
        layer.cornerRadius = 16
        layer.masksToBounds = true

        fallbackGradient.colors = [
            UIColor(red: 1.0, green: 0.80, blue: 0.66, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.52, blue: 0.22, alpha: 1).cgColor
        ]
        fallbackGradient.startPoint = CGPoint(x: 0.1, y: 0)
        fallbackGradient.endPoint = CGPoint(x: 0.9, y: 1)
        layer.addSublayer(fallbackGradient)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        addSubview(imageView)

        scrimLayer.colors = [
            UIColor.black.withAlphaComponent(0.02).cgColor,
            UIColor.black.withAlphaComponent(0.78).cgColor
        ]
        scrimLayer.startPoint = CGPoint(x: 0.5, y: 0)
        scrimLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(scrimLayer)

        categoryLabel.font = .systemFont(ofSize: 10, weight: .bold)
        categoryLabel.textColor = UIColor(red: 1.0, green: 0.56, blue: 0.25, alpha: 1)
        categoryLabel.numberOfLines = 1
        categoryLabel.lineBreakMode = .byTruncatingTail
        addSubview(categoryLabel)

        headlineLabel.font = .systemFont(ofSize: 18, weight: .bold)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 2
        headlineLabel.lineBreakMode = .byTruncatingTail
        addSubview(headlineLabel)

        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sourceLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingTail
        addSubview(sourceLabel)

        timestampLabel.font = .systemFont(ofSize: 11, weight: .medium)
        timestampLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        timestampLabel.textAlignment = .right
        timestampLabel.numberOfLines = 1
        addSubview(timestampLabel)
    }
}

private extension HomeView {
    var generalNewsContext: String {
        viewModel.allArticles.prefix(12).map(\.chatContext).joined(separator: "\n\n")
    }

    var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resultsSubtitle: String {
        if let query = viewModel.searchFallbackQuery, viewModel.searchFallbackAnswer != nil {
            return "No exact article match for \"\(query)\". Briefly answered from the current feed."
        }

        let count = viewModel.searchMatchedArticles.count
        let noun = count == 1 ? "story" : "stories"
        return "\(count) \(noun) matched \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\""
    }
}

private struct BriefLeadStory: View {
    let article: Article
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Text("1")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(BrieflyTheme.actionFill)
                    .clipShape(Circle())

                Text(article.category.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BrieflyTheme.accent)

                Spacer()

                if let publishedAt = article.publishedAt {
                    LiveTimestampText(date: publishedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.58))
                }
            }

            Text(article.headline)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .lineLimit(3)

            Text(bestBriefSummary(for: article))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.72))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(article.source)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.56))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.38))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private func bestBriefSummary(for article: Article) -> String {
        let summary = article.summaryCards.first ?? article.plainSummary
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BriefDigestRow: View {
    let index: Int
    let article: Article
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BrieflyTheme.accent)
                .frame(width: 24, height: 24)
                .background(BrieflyTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(article.category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BrieflyTheme.accent)

                    if let publishedAt = article.publishedAt {
                        Text("•")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.28))
                        LiveTimestampText(date: publishedAt, foregroundColor: BrieflyTheme.text(colorScheme).opacity(0.56))
                    }
                }

                Text(article.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .lineLimit(2)

                Text(article.source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.54))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private func compactMarketNumber(_ value: Double) -> String {
    let absValue = abs(value)
    if absValue >= 1_000_000_000_000 {
        return String(format: "$%.1fT", value / 1_000_000_000_000)
    }
    if absValue >= 1_000_000_000 {
        return String(format: "$%.1fB", value / 1_000_000_000)
    }
    if absValue >= 1_000_000 {
        return String(format: "$%.1fM", value / 1_000_000)
    }
    return String(format: "$%.0f", value)
}

private struct BriefEmptyCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.16))
                    .frame(width: 46, height: 46)

                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            Text("Building the brief")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text("Briefly is waiting for enough strong stories to make this useful.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    BrieflyTheme.quietSurfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.82), lineWidth: 1)
        }
    }
}

private struct FeaturedCard: View {
    let article: Article

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: article.imageURL, style: .hero)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(article.category.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.82))

                Text(article.headline)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(article.source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(1)

                if let publishedAt = article.publishedAt {
                    LiveTimestampText(date: publishedAt, foregroundColor: .white.opacity(0.72))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        // Avoid expensive offscreen rendering from shape clipping during paging.
        .cornerRadius(16, antialiased: false)
    }
}

struct ArticleRow: View {
    let article: Article
    let isSaved: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(url: article.imageURL, style: .thumbnail)
                .frame(width: 92, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(article.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text(article.source)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
                    .lineLimit(1)

                if let publishedAt = article.publishedAt {
                    LiveTimestampText(date: publishedAt, foregroundColor: BrieflyTheme.accent)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct LiveTimestampText: View {
    let date: Date
    var foregroundColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(relativeString(now: context.date))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foregroundColor)
        }
    }

    private func relativeString(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))

        if seconds < 60 {
            return "just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) hr ago"
        }

        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}

private struct FeaturedPlaceholderCard: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [BrieflyTheme.elevatedCard, BrieflyTheme.accent.opacity(0.42), BrieflyTheme.accentBlue.opacity(0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.26))
                    .frame(width: 120, height: 16)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 180, height: 18)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .frame(width: 84, height: 12)
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ArticleRowPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(BrieflyTheme.card(colorScheme))
                .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrieflyTheme.card(colorScheme))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrieflyTheme.card(colorScheme))
                    .frame(width: 180, height: 16)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrieflyTheme.card(colorScheme).opacity(0.8))
                    .frame(width: 120, height: 12)
            }
            Spacer()
        }
        .padding(14)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct EmptyPicksState: View {
    let hasSearchText: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.16))
                    .frame(width: 54, height: 54)

                Image(systemName: hasSearchText ? "magnifyingglass.circle" : "newspaper")
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            Text(hasSearchText ? "No stories matched your search." : "No stories available right now.")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .multilineTextAlignment(.center)

            Text(hasSearchText ? "Briefly should now answer with AI instead of going empty." : "Pull to refresh later or check your API key.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    BrieflyTheme.quietSurfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.82), lineWidth: 1)
        }
    }
}

private struct AIFallbackSearchCard: View {
    let query: String
    let answer: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No direct article match for \"\(query)\"")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text("Briefly answered using the latest feed:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BrieflyTheme.accent)

            Text(answer)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text("Refresh or try a broader query for new matching stories.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.text(colorScheme).opacity(0.12), lineWidth: 1)
        }
    }

}

private struct AllArticlesView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var selectedArticle: Article?
    @Binding var isShowingAuth: Bool
    let session: UserSession?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BrieflyTheme.premiumBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hot News")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        Text("World, politics, conflict, technology, business, and sports in plain English.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
                    }

                    if !AppConfig.shared.hasNewsAPI {
                        Text("Showing demo stories. Live news is temporarily unavailable.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(BrieflyTheme.card(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let answer = viewModel.searchFallbackAnswer, let query = viewModel.searchFallbackQuery {
                        AIFallbackSearchCard(query: query, answer: answer)
                    } else if viewModel.displayedAllArticles.isEmpty {
                        EmptyPicksState(hasSearchText: false)
                    } else {
                        ForEach(feedItems(from: viewModel.displayedAllArticles)) { item in
                            feedRow(for: item)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load(session: session, force: true, desiredCount: 72)
        }
        .task {
            if viewModel.allArticles.count < 48 {
                await viewModel.load(session: session, desiredCount: 72)
            }
        }
    }

    private func bookmarkTitle(for article: Article) -> String {
        guard session != nil else { return "Sign In to Save" }
        return viewModel.savedIDs.contains(article.id) ? "Remove Bookmark" : "Save"
    }

    private func handleBookmark(_ article: Article) {
        guard session != nil else {
            Haptics.selection()
            isShowingAuth = true
            return
        }

        Task {
            Haptics.impact(.light)
            await viewModel.toggleSave(article: article, session: session)
        }
    }

    private func feedItems(from articles: [Article]) -> [ArticleFeedItem] {
        NativeAdInserter.articleItems(
            from: articles,
            placement: .category,
            interval: 5,
            minimumContentBeforeFirstAd: 5
        )
    }

    private func compactMarketNumber(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000_000_000 {
            return String(format: "$%.1fT", value / 1_000_000_000_000)
        }
        if absValue >= 1_000_000_000 {
            return String(format: "$%.1fB", value / 1_000_000_000)
        }
        if absValue >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        }
        return String(format: "$%.0f", value)
    }

    @ViewBuilder
    private func feedRow(for item: ArticleFeedItem) -> some View {
        switch item {
        case .article(let article):
            Button {
                selectedArticle = article
            } label: {
                ArticleRow(article: article, isSaved: viewModel.savedIDs.contains(article.id))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(bookmarkTitle(for: article)) {
                    handleBookmark(article)
                }
            }
        case .nativeAd(let slot):
            NativeAdCard(slot: slot)
        }
    }
}

private extension Date {
    var relativeBrieflyTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
