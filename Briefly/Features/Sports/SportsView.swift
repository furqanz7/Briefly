import SwiftUI

struct SportsView: View {
    @StateObject private var viewModel = SportsViewModel()
    @State private var selectedMatch: LiveMatch?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        searchBar
                        trendingLiveSection
                        feedRow
                        sportsNativeAd
                        filterRow
                        content
                    }
                    .frame(width: max(proxy.size.width - 40, 0), alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .clipped()
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .navigationBarHidden(true)
            .refreshable {
                await viewModel.load(force: true)
            }
            .task {
                await viewModel.startLiveUpdates()
            }
            .sheet(item: $selectedMatch) { match in
                LiveMatchDetailView(match: match)
            }
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sports")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("Live scores, fixtures and results")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondary(colorScheme))
                }

                Spacer(minLength: 16)

                CircleIconButton(systemName: "arrow.clockwise", size: 46, isLoading: viewModel.isLoading) {
                    Task { await viewModel.load(force: true) }
                }
                .disabled(viewModel.isLoading)
            }

            SportsSummaryStrip(
                liveCount: matchCount(in: viewModel.sports),
                upcomingCount: matchCount(in: viewModel.upcomingSports),
                recentCount: matchCount(in: viewModel.recentSports),
                lastUpdatedAt: viewModel.lastUpdatedAt
            )
        }
    }

    private var feedRow: some View {
        SportsFeedSelector(selectedFeed: viewModel.selectedFeed) { feed in
            viewModel.selectFeed(feed)
        }
    }

    @ViewBuilder
    private var sportsNativeAd: some View {
        NativeAdCard(
            slot: NativeAdSlot(
                id: "sports-\(viewModel.selectedFeed.rawValue)",
                placement: .sports
            )
        )
    }

    @ViewBuilder
    private var trendingLiveSection: some View {
        let matches = trendingLiveMatches
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.orange)

                    Text("Trending live")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(BrieflyTheme.primaryText)

                    Spacer()

                    Text("\(matches.count)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(BrieflyTheme.cardBase)
                        .clipShape(Capsule())
                }

                VStack(spacing: 10) {
                    ForEach(matches) { item in
                        Button {
                            selectedMatch = item.match
                        } label: {
                            TrendingLiveCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var filterRow: some View {
        if !viewModel.currentSports.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                SportsFilterPill(
                    title: "All",
                    icon: "sportscourt.fill",
                    isSelected: viewModel.selectedSportID == "all"
                ) {
                    viewModel.selectedSportID = "all"
                }

                ForEach(viewModel.currentSports) { sport in
                    SportsFilterPill(
                        title: sport.name,
                        icon: sport.icon,
                        isSelected: viewModel.selectedSportID == sport.id
                    ) {
                        viewModel.selectedSportID = sport.id
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            SportsMessageCard(
                icon: "exclamationmark.triangle.fill",
                title: "Live scores unavailable",
                message: errorMessage
            )
        } else if !viewModel.providerConfigured {
            SportsMessageCard(
                icon: "sportscourt.fill",
                title: "Live scores unavailable",
                message: "Scores are temporarily unavailable. Check back soon."
            )
        } else if viewModel.isLoading && !viewModel.hasCurrentFeedItems {
            loadingStack
        } else if !viewModel.hasCurrentFeedItems {
            SportsMessageCard(
                icon: emptyStateIcon,
                title: viewModel.selectedFeed.emptyTitle,
                message: viewModel.selectedFeed.emptyMessage
            )
        } else if !viewModel.hasVisibleFeedItems {
            SportsMessageCard(
                icon: "magnifyingglass",
                title: "No sports matched",
                message: "Try a team, athlete, league, venue or score."
            )
        } else {
            VStack(spacing: 18) {
                ForEach(viewModel.visibleSports) { sport in
                    LiveSportBlock(
                        sport: sport,
                        feed: viewModel.selectedFeed,
                        selectedMatch: $selectedMatch
                    )
                }
            }
        }
    }

    private var emptyStateIcon: String {
        switch viewModel.selectedFeed {
        case .live:
            return "moon.zzz.fill"
        case .upcoming:
            return "calendar.badge.clock"
        case .recent:
            return "clock.arrow.circlepath"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)

            TextField("Search teams, athletes, leagues", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.primaryText)
                .tint(BrieflyTheme.accent)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BrieflyTheme.cardBase)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }

    private var loadingStack: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                SportsLoadingCard(index: index)
            }
        }
    }

    private func matchCount(in sports: [LiveSportSection]) -> Int {
        sports.reduce(0) { $0 + $1.matchCount }
    }

    private var trendingLiveMatches: [TrendingLiveItem] {
        viewModel.sports.compactMap { sport in
            guard let match = sport.competitions.lazy.flatMap(\.matches).first else {
                return nil
            }
            return TrendingLiveItem(sport: sport, match: match)
        }
    }
}

private struct TrendingLiveItem: Identifiable {
    let sport: LiveSportSection
    let match: LiveMatch

    var id: String {
        "\(sport.id)-\(match.id)"
    }
}

private struct TrendingLiveCard: View {
    let item: TrendingLiveItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: item.sport.icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)

                Text(item.sport.name)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)

                    Text(item.match.liveBadgeText.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: 10) {
                TeamScoreText(name: item.match.homeName, score: item.match.homeScore, alignment: .leading)

                Text(item.match.clock ?? item.match.period ?? item.match.status)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)

                TeamScoreText(name: item.match.awayName, score: item.match.awayScore, alignment: .trailing)
            }

            Text(item.match.competitionName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct SportsSummaryStrip: View {
    let liveCount: Int
    let upcomingCount: Int
    let recentCount: Int
    let lastUpdatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SportsSummaryTile(title: "Live", value: liveCount, icon: "dot.radiowaves.left.and.right", color: .green)
                SportsSummaryTile(title: "Upcoming", value: upcomingCount, icon: "calendar", color: .orange)
                SportsSummaryTile(title: "Recent", value: recentCount, icon: "checkmark.seal.fill", color: BrieflyTheme.accent)
            }
            .frame(maxWidth: .infinity)

            if let lastUpdatedAt {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Updated \(lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(BrieflyTheme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct SportsSummaryTile: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(color)

                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(color)
            }

            Text("\(value)")
                .font(.system(size: 24, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct SportsFeedSelector: View {
    let selectedFeed: SportsViewModel.Feed
    let action: (SportsViewModel.Feed) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SportsViewModel.Feed.allCases) { feed in
                Button {
                    action(feed)
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Image(systemName: feed.icon)
                                .font(.system(size: 12, weight: .heavy))

                            Text(feed.title)
                                .font(.system(size: 13, weight: .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Image(systemName: feed.icon)
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(selectedFeed == feed ? Color.white : BrieflyTheme.secondaryText)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        if selectedFeed == feed {
                            BrieflyTheme.actionGradient
                        } else {
                            Color.clear
                        }
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct SportsFilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))

                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(isSelected ? Color.white : BrieflyTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 14)
            .background {
                if isSelected {
                    BrieflyTheme.actionGradient
                } else {
                    BrieflyTheme.elevatedCard
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(isSelected ? Color.white.opacity(0.12) : BrieflyTheme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveSportBlock: View {
    let sport: LiveSportSection
    let feed: SportsViewModel.Feed
    @Binding var selectedMatch: LiveMatch?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: sport.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.accent)

                Text(sport.name)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(BrieflyTheme.primaryText)

                Spacer()

                Text("\(sport.matchCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(BrieflyTheme.cardBase)
                    .clipShape(Capsule())
            }

            VStack(spacing: 12) {
                ForEach(sport.competitions) { competition in
                    LiveCompetitionBlock(
                        competition: competition,
                        feed: feed,
                        selectedMatch: $selectedMatch
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveCompetitionBlock: View {
    let competition: LiveCompetition
    let feed: SportsViewModel.Feed
    @Binding var selectedMatch: LiveMatch?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(competition.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(BrieflyTheme.primaryText)

                if let country = competition.country, !country.isEmpty {
                    Text(country)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
            }

            VStack(spacing: 10) {
                ForEach(competition.matches) { match in
                    Button {
                        selectedMatch = match
                    } label: {
                        LiveMatchRow(match: match, feed: feed)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.cardBase.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct LiveMatchRow: View {
    let match: LiveMatch
    let feed: SportsViewModel.Feed

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TeamLabel(name: match.homeName, score: match.homeScore, logoURL: match.homeLogoURL)

                VStack(spacing: 6) {
                    Text(centerText)
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.68)

                    Text(statusText)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 66)

                TeamLabel(name: match.awayName, score: match.awayScore, logoURL: match.awayLogoURL, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            if let metadataText {
                Text(metadataText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }

    private var centerText: String {
        switch feed {
        case .upcoming:
            return "vs"
        case .live, .recent:
            if match.homeScore == nil && match.awayScore == nil,
               let scoreSummary = match.scoreSummary,
               !scoreSummary.isEmpty {
                return scoreSummary
            }
            return match.clock ?? match.period ?? (feed == .recent ? "Final" : "Live")
        }
    }

    private var statusText: String {
        switch feed {
        case .live:
            return match.liveBadgeText.uppercased()
        case .upcoming:
            if let startsAtText {
                return startsAtText
            }
            return "UPCOMING"
        case .recent:
            if let detail = match.statusDetail, !detail.isEmpty {
                return detail.uppercased()
            }
            return match.status.isEmpty ? "RESULT" : match.status.uppercased()
        }
    }

    private var statusColor: Color {
        switch feed {
        case .live:
            return .green
        case .upcoming:
            return .orange
        case .recent:
            return BrieflyTheme.accent
        }
    }

    private var metadataText: String? {
        if feed == .upcoming, let startsAt = match.startsAt {
            return startsAt.formatted(date: .abbreviated, time: .shortened)
        }

        if let note = match.note, !note.isEmpty {
            return note
        }

        if let venue = match.venue, !venue.isEmpty {
            return venue
        }

        if let detail = match.statusDetail, !detail.isEmpty {
            return detail
        }

        return nil
    }

    private var startsAtText: String? {
        guard let startsAt = match.startsAt else { return nil }
        return startsAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct TeamLabel: View {
    let name: String
    let score: String?
    let logoURL: URL?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 7) {
            AsyncImage(url: logoURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "shield.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.6))
            }
            .frame(width: 26, height: 26)
            .padding(7)
            .background(BrieflyTheme.cardBase)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
            }

            Text(name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .minimumScaleFactor(0.78)

            if let score, !score.isEmpty {
                Text(score)
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                    .minimumScaleFactor(0.68)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }
}

private struct TeamScoreText: View {
    let name: String
    let score: String?
    let alignment: HorizontalAlignment

    private var frameAlignment: Alignment {
        alignment == .trailing ? .trailing : .leading
    }

    private var textAlignment: TextAlignment {
        alignment == .trailing ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .multilineTextAlignment(textAlignment)

            if let score, !score.isEmpty {
                Text(score)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .multilineTextAlignment(textAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

private struct SportsLoadingCard: View {
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(index == 0 ? 0.24 : 0.14))
                    .frame(width: 48, height: 48)

                Image(systemName: index == 0 ? "dot.radiowaves.left.and.right" : "sportscourt.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(index == 0 ? .green : BrieflyTheme.accent)
            }

            VStack(alignment: .leading, spacing: 10) {
                SportsSkeletonLine(widthFactor: index == 0 ? 0.76 : 0.62, height: 15)
                SportsSkeletonLine(widthFactor: 0.92, height: 11)
                SportsSkeletonLine(widthFactor: index == 2 ? 0.66 : 0.80, height: 11)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                SportsSkeletonLine(widthFactor: 1, height: 20)
                    .frame(width: 46)
                SportsSkeletonLine(widthFactor: 1, height: 10)
                    .frame(width: 32)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    LinearGradient(
                        colors: [
                            BrieflyTheme.accent.opacity(0.13),
                            BrieflyTheme.accentBlue.opacity(0.06),
                            BrieflyTheme.elevatedCard.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
        }
    }
}

private struct SportsSkeletonLine: View {
    let widthFactor: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(BrieflyTheme.secondaryText.opacity(0.14))
                .frame(width: proxy.size.width * widthFactor, height: height)
        }
        .frame(height: height)
    }
}

private struct SportsMessageCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.16))
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            Text(title)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.94))
                .overlay {
                    BrieflyTheme.quietSurfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
        }
    }
}

private struct LiveMatchDetailView: View {
    let match: LiveMatch
    private static let liveDetailRefreshInterval: Duration = .seconds(60)
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var detailMatch: LiveMatch
    @State private var scoreboardSections: [ScoreboardSection]
    @State private var isLoadingDetail = false
    @State private var isRefreshingDetail = false
    @State private var detailError: String?
    @State private var didPinWidgetMatch = false
    @State private var didFollowMatchTeams = false
    @State private var isFollowingTeams = false
    @State private var followNotice: String?
    @State private var authPrompt: AuthPrompt?
    private let sportsService = SportsService()
    private let followedSportsService = FollowedSportsService()

    init(match: LiveMatch) {
        self.match = match
        _detailMatch = State(initialValue: match)
        _scoreboardSections = State(initialValue: match.scoreboardSections ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(detailMatch.sportName)
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(BrieflyTheme.accent)

                        Text(detailMatch.competitionName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.secondaryText)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        DetailTeam(
                            name: detailMatch.homeName,
                            score: detailMatch.homeScore,
                            logoURL: detailMatch.homeLogoURL,
                            isLeading: true
                        )

                        VStack(spacing: 8) {
                            Text(detailCenterText)
                                .font(.system(size: 16, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(BrieflyTheme.primaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.68)

                            Text(detailStatusText)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(detailStatusColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(detailStatusColor.opacity(0.12))
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(width: 86)

                        DetailTeam(
                            name: detailMatch.awayName,
                            score: detailMatch.awayScore,
                            logoURL: detailMatch.awayLogoURL,
                            isLeading: false
                        )
                    }
                    .padding(20)
                    .background(BrieflyTheme.elevatedCard)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(BrieflyTheme.divider, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(label: "Status", value: detailMatch.statusDetail ?? detailMatch.status)
                        if let period = detailMatch.period, !period.isEmpty {
                            DetailRow(label: "Period", value: period)
                        }
                        if let venue = detailMatch.venue, !venue.isEmpty {
                            DetailRow(label: "Venue", value: venue)
                        }
                        if let country = detailMatch.country, !country.isEmpty {
                            DetailRow(label: "Country", value: country)
                        }
                        if let note = detailMatch.note, !note.isEmpty {
                            DetailRow(label: "Update", value: note)
                        }
                    }
                    .padding(18)
                    .background(BrieflyTheme.cardBase)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(BrieflyTheme.divider, lineWidth: 1)
                    }

                    Button {
                        guard appState.session != nil else {
                            authPrompt = AuthPrompt(
                                title: "Sign in to add live matches",
                                message: "Sign in before pinning live matches so your Home Screen widget can use your account data."
                            )
                            return
                        }
                        WidgetSnapshotStore.pinMatch(detailMatch)
                        didPinWidgetMatch = true
                        Haptics.success()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: didPinWidgetMatch ? "checkmark.circle.fill" : "pin.fill")
                                .font(.system(size: 15, weight: .heavy))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(didPinWidgetMatch ? "Live match widget updated" : "Show this match on widget")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(BrieflyTheme.primaryText)

                                Text("Your Sports Home Screen widget will use this match.")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BrieflyTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Spacer(minLength: 8)
                        }
                        .foregroundStyle(didPinWidgetMatch ? .green : BrieflyTheme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background((didPinWidgetMatch ? Color.green : BrieflyTheme.accent).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke((didPinWidgetMatch ? Color.green : BrieflyTheme.accent).opacity(0.28), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show this match on the Sports widget")

                    Button {
                        Task { await followMatchTeams() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: didFollowMatchTeams ? "bell.badge.fill" : "bell.fill")
                                .font(.system(size: 15, weight: .heavy))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(didFollowMatchTeams ? "Live alerts enabled" : "Follow teams for live alerts")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(BrieflyTheme.primaryText)

                                Text(followNotice ?? "Briefly will use these teams for targeted Sports alerts.")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BrieflyTheme.secondaryText)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                            }

                            Spacer(minLength: 8)

                            if isFollowingTeams {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(BrieflyTheme.accentBlue)
                            }
                        }
                        .foregroundStyle(didFollowMatchTeams ? .green : BrieflyTheme.accentBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background((didFollowMatchTeams ? Color.green : BrieflyTheme.accentBlue).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke((didFollowMatchTeams ? Color.green : BrieflyTheme.accentBlue).opacity(0.28), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFollowingTeams)
                    .accessibilityLabel("Follow teams for Sports notifications")

                    if isLoadingDetail && scoreboardSections.isEmpty {
                        ProgressView("Loading scoreboard")
                            .tint(BrieflyTheme.accent)
                            .foregroundStyle(BrieflyTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let detailError, scoreboardSections.isEmpty {
                        SportsMessageCard(
                            icon: "chart.bar.doc.horizontal.fill",
                            title: "Scoreboard unavailable",
                            message: detailError
                        )
                    }

                    ForEach(scoreboardSections) { section in
                        ScoreboardSectionView(section: section)
                    }
                }
                .padding(20)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadDetail()
                await startDetailLiveUpdates()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await refreshDetail() }
                    } label: {
                        if isRefreshingDetail {
                            ProgressView()
                                .controlSize(.small)
                                .tint(BrieflyTheme.accent)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .disabled(isRefreshingDetail || isLoadingDetail)
                    .accessibilityLabel("Refresh match")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $authPrompt) { prompt in
            AccountGateView(
                title: prompt.title,
                message: prompt.message,
                buttonTitle: prompt.buttonTitle
            )
            .environmentObject(appState)
            .padding(20)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
        }
    }

    private func refreshDetail() async {
        guard !isRefreshingDetail, !isLoadingDetail else { return }
        isRefreshingDetail = true
        let startedAt = Date()

        await loadDetail(force: true)

        let elapsed = Date().timeIntervalSince(startedAt)
        let minimumVisibleDuration: TimeInterval = 0.45
        if elapsed < minimumVisibleDuration {
            let remaining = UInt64((minimumVisibleDuration - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remaining)
        }

        isRefreshingDetail = false
    }

    private func loadDetail(force _: Bool = false) async {
        guard !isLoadingDetail else { return }
        isLoadingDetail = true
        detailError = nil

        do {
            let response = try await sportsService.fetchMatchDetail(for: match)
            if shouldIgnoreDetailResponse(response) {
                if scoreboardSections.isEmpty {
                    scoreboardSections = match.scoreboardSections ?? []
                }
                detailMatch = match
                isLoadingDetail = false
                return
            }
            detailMatch = response.match
            scoreboardSections = response.scoreboardSections
        } catch {
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }

    private func startDetailLiveUpdates() async {
        guard shouldAutoRefreshDetail else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.liveDetailRefreshInterval)
            if Task.isCancelled { break }
            guard shouldAutoRefreshDetail else { break }
            await loadDetail(force: true)
        }
    }

    private func followMatchTeams() async {
        guard !isFollowingTeams else { return }
        guard let session = appState.session else {
            authPrompt = AuthPrompt(
                title: "Sign in to follow teams",
                message: "Briefly uses followed teams to send focused Sports alerts instead of broad sports spam."
            )
            return
        }

        isFollowingTeams = true
        defer { isFollowingTeams = false }

        do {
            try await followedSportsService.followTeams(from: detailMatch, session: session)
            didFollowMatchTeams = true
            followNotice = "Sports alerts will watch \(detailMatch.homeName) and \(detailMatch.awayName)."
            Haptics.success()
        } catch {
            followNotice = "Could not follow these teams yet."
            Haptics.error()
        }
    }

    private var shouldAutoRefreshDetail: Bool {
        !isFinal && !isUpcoming
    }

    private func shouldIgnoreDetailResponse(_ response: LiveMatchDetailResponse) -> Bool {
        guard !(match.scoreboardSections ?? []).isEmpty || !scoreboardSections.isEmpty else {
            return false
        }

        let homeName = response.match.homeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let awayName = response.match.awayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = response.match.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let statusDetail = response.match.statusDetail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasPlaceholderTeams = homeName == "home" && awayName == "away"
        let hasBooleanStatus = status == "true" || statusDetail == "true"
        let hasOnlyWaitingRow = response.scoreboardSections.count == 1
            && response.scoreboardSections.first?.rows.count == 1
            && response.scoreboardSections.first?.rows.first?.id == "waiting"

        return hasPlaceholderTeams || hasBooleanStatus || hasOnlyWaitingRow
    }

    private var detailCenterText: String {
        if isUpcoming {
            return "vs"
        }
        if isFinal {
            return "Final"
        }
        return detailMatch.clock ?? detailMatch.period ?? "Live"
    }

    private var detailStatusText: String {
        if isUpcoming {
            if let startsAt = detailMatch.startsAt {
                return startsAt.formatted(date: .omitted, time: .shortened)
            }
            return "UPCOMING"
        }

        if isFinal {
            return (detailMatch.statusDetail ?? detailMatch.status).uppercased()
        }

        return detailMatch.liveBadgeText.uppercased()
    }

    private var detailStatusColor: Color {
        if isUpcoming {
            return .orange
        }
        if isFinal {
            return BrieflyTheme.accent
        }
        return .green
    }

    private var isUpcoming: Bool {
        guard let startsAt = detailMatch.startsAt else { return false }
        return startsAt > Date()
    }

    private var isFinal: Bool {
        let status = "\(detailMatch.status) \(detailMatch.statusDetail ?? "")".lowercased()
        return status.contains("final") || status.contains("result") || status.contains("finished") || status.contains("complete")
    }
}

private struct ScoreboardSectionView: View {
    let section: ScoreboardSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(BrieflyTheme.primaryText)

                if let subtitle = section.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    if !section.columns.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        ScoreboardGridRow(cells: section.columns, isHeader: true, note: nil)
                    }

                    ForEach(section.rows) { row in
                        ScoreboardGridRow(cells: row.cells, isHeader: false, note: row.note)
                    }
                }
                .frame(minWidth: 290, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrieflyTheme.divider, lineWidth: 1)
            }
        }
        .padding(18)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct ScoreboardGridRow: View {
    let cells: [String]
    let isHeader: Bool
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    Text(cell)
                        .font(.system(size: isHeader ? 11 : 12, weight: isHeader ? .heavy : (index == 0 ? .semibold : .bold)))
                        .foregroundStyle(isHeader ? BrieflyTheme.secondaryText : BrieflyTheme.primaryText)
                        .lineLimit(index == 0 ? 2 : 2)
                        .minimumScaleFactor(0.72)
                        .frame(
                            minWidth: index == 0 ? 124 : 48,
                            maxWidth: index == 0 ? 180 : 74,
                            alignment: index == 0 ? .leading : .trailing
                        )
                        .monospacedDigit()
                }
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHeader ? BrieflyTheme.elevatedCard.opacity(0.72) : BrieflyTheme.elevatedCard.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrieflyTheme.divider)
                .frame(height: 1)
        }
    }
}

private struct DetailTeam: View {
    let name: String
    let score: String?
    let logoURL: URL?
    let isLeading: Bool

    private var alignment: HorizontalAlignment {
        isLeading ? .leading : .trailing
    }

    private var textAlignment: TextAlignment {
        isLeading ? .leading : .trailing
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 9) {
            AsyncImage(url: logoURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.6))
            }
            .frame(width: 42, height: 42)
            .padding(10)
            .background(BrieflyTheme.cardBase)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
            }

            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(BrieflyTheme.primaryText)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            if let score, !score.isEmpty {
                Text(score)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .frame(width: 84, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrieflyTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
