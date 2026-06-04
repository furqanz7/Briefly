import SafariServices
import SwiftUI
import UIKit
import WebKit

struct BooksView: View {
    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case saved = "Saved"
        case downloaded = "Downloaded"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .saved: return "bookmark.fill"
            case .downloaded: return "tray.and.arrow.down.fill"
            }
        }
    }

    @StateObject private var viewModel = BooksViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var authPrompt: AuthPrompt?
    @State private var libraryFilter: LibraryFilter = .all
    @State private var isGoalEditorPresented = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    readingTracker
                    searchBar
                    genreRow
                    providerStatus

                    if viewModel.isLoading {
                        BooksLoadingCard()
                    } else if let errorMessage = viewModel.errorMessage {
                        BooksEmptyCard(title: "Books unavailable", message: errorMessage)
                    } else {
                        if let featured = viewModel.featuredBook {
                            featuredCard(featured)
                        }

                        booksNativeAd
                        libraryGrid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 120)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .navigationBarHidden(true)
            .refreshable {
                await viewModel.search()
                await viewModel.loadAccountBackedLibrary(session: appState.session)
            }
            .task {
                await viewModel.load(session: appState.session)
            }
            .onChange(of: appState.session?.userID) {
                Task { await viewModel.loadAccountBackedLibrary(session: appState.session) }
            }
            .sheet(item: $viewModel.selectedBook) { book in
                BookDetailView(
                    book: book,
                    isSaved: viewModel.savedBooks.contains(book),
                    isDownloaded: viewModel.downloadedIDs.contains(book.id),
                    readingMinutesToday: viewModel.readingMinutesToday,
                    readingGoalMinutes: viewModel.readingGoalMinutes,
                    readingSummary: viewModel.readingSummary,
                    onToggleSave: { viewModel.toggleSave(book, session: appState.session) },
                    onDownload: { viewModel.markDownloaded(book, session: appState.session) },
                    onAddReadingSeconds: { viewModel.addReadingSeconds($0, session: appState.session) },
                    onResetReading: { viewModel.resetReadingMinutes(session: appState.session) }
                )
                .environmentObject(appState)
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
            .fullScreenCover(isPresented: $isGoalEditorPresented) {
                ReadingGoalEditor(
                    goalMinutes: viewModel.readingGoalMinutes,
                    onSave: { viewModel.updateReadingGoal(minutes: $0, session: appState.session) }
                )
                .presentationBackground(.clear)
            }
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Books")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))

                Text("\(viewModel.visibleBooks.count) titles  •  \(viewModel.selectedGenre.rawValue)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondary(colorScheme))
            }

            Spacer()

            Button {
                Task { await viewModel.search() }
            } label: {
                ZStack {
                    Circle()
                        .fill(BrieflyTheme.elevatedCard)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
                        }

                    if viewModel.isLoading {
                        ProgressView()
                            .tint(BrieflyTheme.primaryText)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh books")
        }
    }

    private var readingTracker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daily reading")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.92))
                        .textCase(.uppercase)
                    Text(formatDuration(minutes: viewModel.readingSummary.todayMinutes))
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                }

                Spacer()

                HStack(spacing: 7) {
                    Button {
                        requireAccount(
                            title: "Sign in to set a goal",
                            message: "Sign in before setting a reading goal so Briefly can keep it with your account.",
                            action: { isGoalEditorPresented = true }
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.readingSummary.hasCustomGoal ? "target" : "plus")
                                .font(.system(size: 11, weight: .heavy))
                            Text(readingGoalLabel)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(viewModel.readingSummary.hasCustomGoal ? BrieflyTheme.primaryText.opacity(0.86) : BrieflyTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(viewModel.readingSummary.hasCustomGoal ? BrieflyTheme.elevatedCard.opacity(0.9) : BrieflyTheme.accent.opacity(0.12))
                        .fixedSize(horizontal: true, vertical: false)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(viewModel.readingSummary.hasCustomGoal ? BrieflyTheme.divider.opacity(0.75) : BrieflyTheme.accent.opacity(0.26), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        requireAccount(
                            title: "Sign in to track reading",
                            message: "Sign in before tracking reading time so Briefly can keep your progress with your account.",
                            action: { viewModel.resetReadingMinutes(session: appState.session) }
                        )
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(BrieflyTheme.elevatedCard.opacity(0.78))
                            .clipShape(Capsule())
                            .overlay {
                                Circle().stroke(BrieflyTheme.divider.opacity(0.65), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset daily reading")
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrieflyTheme.elevatedCard.opacity(0.78))
                    Capsule()
                        .fill(BrieflyTheme.actionGradient)
                        .frame(width: proxy.size.width * viewModel.readingProgress)
                }
            }
            .frame(height: 9)

            HStack(spacing: 10) {
                ReadingStatTile(title: "Week", value: formatDuration(minutes: viewModel.readingSummary.weekMinutes))
                ReadingStatTile(title: "Month", value: formatDuration(minutes: viewModel.readingSummary.monthMinutes))
                ReadingStatTile(title: "Overall", value: formatDuration(minutes: viewModel.readingSummary.overallMinutes))
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.96))
                .overlay {
                    LinearGradient(
                        colors: [BrieflyTheme.accent.opacity(0.22), BrieflyTheme.accentBlue.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }

    private func requireAccount(title: String, message: String, action: () -> Void) {
        guard appState.session != nil else {
            authPrompt = AuthPrompt(title: title, message: message)
            return
        }

        action()
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)

            TextField("Search books, authors, ISBN", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(BrieflyTheme.primaryText)
                .tint(BrieflyTheme.accent)
                .onSubmit {
                    Task { await viewModel.search() }
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .background(BrieflyTheme.cardBase)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }

    private var genreRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BooksViewModel.Genre.allCases) { genre in
                    Button {
                        viewModel.choose(genre)
                        Task { await viewModel.search() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: genreIcon(genre))
                                .font(.system(size: 12, weight: .heavy))
                            Text(genre.rawValue)
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundStyle(viewModel.selectedGenre == genre ? BrieflyTheme.primaryText : BrieflyTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(viewModel.selectedGenre == genre ? BrieflyTheme.accent.opacity(0.26) : BrieflyTheme.cardBase)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(viewModel.selectedGenre == genre ? BrieflyTheme.accent.opacity(0.46) : BrieflyTheme.divider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func featuredCard(_ book: BookItem) -> some View {
        Button {
            viewModel.selectedBook = book
        } label: {
            HStack(spacing: 16) {
                BookCover(url: book.coverURL, height: 168)
                    .frame(width: 112)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Featured")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.accent)
                        .textCase(.uppercase)

                    Text(book.title)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    Text(book.authorLine)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        BookMetaPill(icon: "clock.fill", text: "\(book.readingMinutes / 60)h")
                        BookMetaPill(icon: "tray.and.arrow.down.fill", text: book.downloadURL == nil ? "Preview" : "Download")
                    }

                    Text(book.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.primaryText.opacity(0.88))
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(BrieflyTheme.cardBase)
                    .overlay {
                        LinearGradient(
                            colors: [BrieflyTheme.accent.opacity(0.24), BrieflyTheme.accentBlue.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(BrieflyTheme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var booksNativeAd: some View {
        if viewModel.visibleBooks.count >= 8 {
            NativeAdCard(
                slot: NativeAdSlot(
                    id: "books-\(viewModel.selectedGenre.rawValue)",
                    placement: .books
                )
            )
        }
    }

    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Library")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                    Spacer()
                    Text(libraryCountText)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }

                libraryFilterRow
            }

            if libraryBooks.isEmpty {
                BooksEmptyCard(
                    title: emptyLibraryTitle,
                    message: emptyLibraryMessage
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(libraryBooks) { book in
                        BookTile(
                            book: book,
                            isSaved: viewModel.savedBooks.contains(book),
                            isDownloaded: viewModel.downloadedIDs.contains(book.id),
                            onOpen: { viewModel.selectedBook = book },
                            onSave: { viewModel.toggleSave(book, session: appState.session) },
                            onDownload: { viewModel.markDownloaded(book, session: appState.session) }
                        )
                    }
                }
            }
        }
    }

    private var libraryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button {
                        libraryFilter = filter
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 12, weight: .heavy))
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundStyle(libraryFilter == filter ? BrieflyTheme.primaryText : BrieflyTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(libraryFilter == filter ? BrieflyTheme.accent.opacity(0.26) : BrieflyTheme.cardBase)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(libraryFilter == filter ? BrieflyTheme.accent.opacity(0.46) : BrieflyTheme.divider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var libraryBooks: [BookItem] {
        switch libraryFilter {
        case .all:
            return viewModel.visibleBooks
        case .saved:
            return viewModel.visibleBooks.filter { viewModel.savedBooks.contains($0) }
        case .downloaded:
            return viewModel.visibleBooks.filter { viewModel.downloadedIDs.contains($0.id) }
        }
    }

    private var libraryCountText: String {
        switch libraryFilter {
        case .all:
            return "\(viewModel.visibleBooks.count) titles"
        case .saved:
            return "\(libraryBooks.count) saved"
        case .downloaded:
            return "\(libraryBooks.count) downloaded"
        }
    }

    private var emptyLibraryTitle: String {
        switch libraryFilter {
        case .all:
            return "No books found"
        case .saved:
            return "No saved books"
        case .downloaded:
            return "No downloaded books"
        }
    }

    private var emptyLibraryMessage: String {
        switch libraryFilter {
        case .all:
            return "Try a different search or genre."
        case .saved:
            return "Save a book from the Library or book detail view to see it here."
        case .downloaded:
            return "Download a readable book or preview to keep it in this filtered view."
        }
    }

    private func genreIcon(_ genre: BooksViewModel.Genre) -> String {
        switch genre {
        case .all: return "books.vertical.fill"
        case .fiction: return "sparkles"
        case .business: return "chart.line.uptrend.xyaxis"
        case .biography: return "person.text.rectangle.fill"
        case .fantasy: return "wand.and.stars"
        case .history: return "building.columns.fill"
        case .science: return "atom"
        case .technology: return "cpu.fill"
        case .romance: return "heart.fill"
        case .classics: return "text.book.closed.fill"
        }
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    @ViewBuilder
    private var providerStatus: some View {
        if let message = viewModel.providerMessage, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)

                Text(message)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(BrieflyTheme.elevatedCard.opacity(0.74), in: Capsule())
            .overlay {
                Capsule().stroke(BrieflyTheme.divider.opacity(0.72), lineWidth: 1)
            }
        }
    }

    private var readingGoalLabel: String {
        viewModel.readingSummary.hasCustomGoal ? "\(viewModel.readingGoalMinutes)m goal" : "Set goal"
    }
}

private struct BookTile: View {
    let book: BookItem
    let isSaved: Bool
    let isDownloaded: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    let onDownload: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    BookCover(url: book.coverURL, height: 182)

                    HStack(spacing: 7) {
                        Button(action: onSave) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.primaryText)
                                .frame(width: 34, height: 34)
                                .background(BrieflyTheme.backgroundBase.opacity(0.74))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button(action: onDownload) {
                            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(isDownloaded ? .green : BrieflyTheme.primaryText)
                                .frame(width: 34, height: 34)
                                .background(BrieflyTheme.backgroundBase.opacity(0.74))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(book.downloadURL == nil)
                        .opacity(book.downloadURL == nil ? 0.45 : 1)
                    }
                    .padding(10)
                }

                Text(book.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(book.authorLine)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    BookMetaPill(icon: "network", text: book.source)
                    BookMetaPill(icon: "book.closed.fill", text: book.genre)
                    if let rating = book.rating {
                        BookMetaPill(icon: "star.fill", text: String(format: "%.1f", rating))
                    }
                }
            }
            .padding(12)
            .background(BrieflyTheme.cardBase)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BrieflyTheme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BookDetailView: View {
    let book: BookItem
    let isSaved: Bool
    let isDownloaded: Bool
    let readingMinutesToday: Int
    let readingGoalMinutes: Int
    let readingSummary: ReadingSummary
    let onToggleSave: () -> Void
    let onDownload: () -> Void
    let onAddReadingSeconds: (Int) -> Void
    let onResetReading: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var browserURL: URL?
    @State private var authPrompt: AuthPrompt?
    @State private var isReaderPresented = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 18) {
                        BookCover(url: book.coverURL, height: 220)
                            .frame(width: 146)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(book.source.uppercased())
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.accent)
                            Text(book.title)
                                .font(.system(size: 30, weight: .heavy))
                                .lineSpacing(2)
                                .foregroundStyle(BrieflyTheme.primaryText)
                            Text(book.authorLine)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.secondaryText)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        BookFact(icon: "books.vertical.fill", title: "Genre", value: book.genre)
                        BookFact(icon: "clock.fill", title: "Read time", value: "\(book.readingMinutes / 60) hr")
                        BookFact(icon: "calendar", title: "Published", value: book.publishedYear.isEmpty ? "Unknown" : book.publishedYear)
                        BookFact(icon: "tray.and.arrow.down.fill", title: "Access", value: book.availability.rawValue)
                    }

                    BookDetailBlock(title: "About", text: book.description)

                    VStack(alignment: .leading, spacing: 13) {
                        Text("Reading tracker")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)

                        Text("\(readingMinutesToday) of \(readingGoalMinutes) minutes today")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.secondaryText)

                        HStack(spacing: 10) {
                            ReadingStatTile(title: "Week", value: formatDuration(minutes: readingSummary.weekMinutes))
                            ReadingStatTile(title: "Month", value: formatDuration(minutes: readingSummary.monthMinutes))
                            ReadingStatTile(title: "Overall", value: formatDuration(minutes: readingSummary.overallMinutes))
                            ReadingIconButton(systemName: "arrow.counterclockwise") {
                                requireAccount(
                                    title: "Sign in to track reading",
                                    message: "Sign in before tracking reading time so Briefly can keep your progress with your account.",
                                    action: onResetReading
                                )
                            }
                        }
                    }
                    .padding(18)
                    .background(BrieflyTheme.cardBase)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(BrieflyTheme.divider, lineWidth: 1)
                    }

                    actionButtons
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                    }
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { browserURL != nil },
                set: { if !$0 { browserURL = nil } }
            )
        ) {
            if let browserURL {
                ReadingTimedSafariSheet(url: browserURL, onReadingEnded: onAddReadingSeconds)
            }
        }
        .fullScreenCover(isPresented: $isReaderPresented) {
            BookReaderView(book: book, onReadingEnded: onAddReadingSeconds)
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

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                requireAccount(
                    title: "Sign in to read books",
                    message: "Sign in before reading books in Briefly so your library and reading time stay with your account."
                ) {
                    isReaderPresented = true
                }
            } label: {
                Text("Read in Briefly")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(BrieflyTheme.actionGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    requireAccount(
                        title: "Sign in to save books",
                        message: "Sign in before saving books so Briefly can keep your library with your account.",
                        action: onToggleSave
                    )
                } label: {
                    BookActionLabel(icon: isSaved ? "bookmark.fill" : "bookmark", title: isSaved ? "Saved" : "Save")
                }
                .buttonStyle(.plain)

                Button {
                    requireAccount(
                        title: "Sign in to download books",
                        message: "Sign in before downloading books so Briefly can keep your library with your account."
                    ) {
                        onDownload()
                        browserURL = book.downloadURL ?? book.previewURL
                    }
                } label: {
                    BookActionLabel(icon: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill", title: isDownloaded ? "Downloaded" : "Download")
                }
                .buttonStyle(.plain)
                .disabled(book.downloadURL == nil && book.previewURL == nil)
                .opacity(book.downloadURL == nil && book.previewURL == nil ? 0.5 : 1)
            }

            if let previewURL = book.previewURL {
                Button {
                    requireAccount(
                        title: "Sign in to read books",
                        message: "Sign in before reading books in Briefly so your library and reading time stay with your account."
                    ) {
                        browserURL = previewURL
                    }
                } label: {
                    Text("Open Provider Preview")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(BrieflyTheme.cardBase)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(BrieflyTheme.divider, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requireAccount(title: String, message: String, action: () -> Void) {
        guard appState.session != nil else {
            authPrompt = AuthPrompt(title: title, message: message)
            return
        }

        action()
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

private struct BookReaderView: View {
    let book: BookItem
    let onReadingEnded: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fontScale: CGFloat = 1
    @State private var showWebReader = true
    @State private var readingStartedAt = Date()

    private var readerURL: URL? {
        book.downloadURL ?? book.previewURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                readerHeader

                if showWebReader, let readerURL {
                    BookWebReader(url: readerURL)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(BrieflyTheme.divider, lineWidth: 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(book.title)
                                .font(.system(size: 30 * fontScale, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.primaryText)
                                .lineSpacing(4)

                            Text(book.authorLine)
                                .font(.system(size: 15 * fontScale, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.secondaryText)

                            Text(readerText)
                                .font(.system(size: 18 * fontScale, weight: .semibold))
                                .foregroundStyle(BrieflyTheme.primaryText.opacity(0.92))
                                .lineSpacing(9)
                        }
                        .padding(24)
                    }
                    .background(BrieflyTheme.cardBase)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(BrieflyTheme.divider, lineWidth: 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }

                readerControls
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            readingStartedAt = Date()
        }
        .onDisappear {
            let elapsed = Int(Date().timeIntervalSince(readingStartedAt))
            if elapsed >= 5 {
                onReadingEnded(elapsed)
            }
        }
    }

    private var readerHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .frame(width: 42, height: 42)
                    .background(BrieflyTheme.elevatedCard)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.primaryText)
                    .lineLimit(1)
                Text(book.authorLine)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if readerURL != nil {
                Button {
                    showWebReader.toggle()
                } label: {
                    Image(systemName: showWebReader ? "text.alignleft" : "network")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .frame(width: 42, height: 42)
                        .background(BrieflyTheme.elevatedCard)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showWebReader ? "Show text reader" : "Show provider reader")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var readerControls: some View {
        HStack(spacing: 12) {
            Button {
                fontScale = max(0.82, fontScale - 0.08)
            } label: {
                ReaderControlLabel(title: "A", systemName: "minus")
            }
            .buttonStyle(.plain)

            Button {
                fontScale = min(1.28, fontScale + 0.08)
            } label: {
                ReaderControlLabel(title: "A", systemName: "plus")
            }
            .buttonStyle(.plain)

            Text("Time is tracked automatically while this reader is open.")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(BrieflyTheme.elevatedCard)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var readerText: String {
        let parts = [
            book.description,
            book.publisher.isEmpty ? nil : "Publisher: \(book.publisher)",
            book.publishedYear.isEmpty ? nil : "Published: \(book.publishedYear)",
            book.genre.isEmpty ? nil : "Genre: \(book.genre)",
        ].compactMap { $0 }
        return parts.joined(separator: "\n\n")
    }
}

private struct BookWebReader: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.backgroundColor = .clear
        webView.isOpaque = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct ReaderControlLabel: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: systemName)
        }
        .font(.system(size: 14, weight: .heavy))
        .foregroundStyle(BrieflyTheme.primaryText)
        .frame(width: 72, height: 48)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(Capsule())
    }
}

private struct ReadingTimedSafariSheet: View {
    let url: URL
    let onReadingEnded: (Int) -> Void
    @State private var readingStartedAt = Date()

    var body: some View {
        BookSafariSheet(url: url)
            .onAppear {
                readingStartedAt = Date()
            }
            .onDisappear {
                let elapsed = Int(Date().timeIntervalSince(readingStartedAt))
                if elapsed >= 5 {
                    onReadingEnded(elapsed)
                }
            }
    }
}

private struct BookSafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(BrieflyTheme.accent)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct BookDetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(BrieflyTheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct BookCover: View {
    let url: URL?
    let height: CGFloat

    var body: some View {
        RemoteImage(url: url, style: .detail)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(BrieflyTheme.elevatedCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BrieflyTheme.primaryText.opacity(0.10), lineWidth: 1)
            }
    }
}

private struct BookMetaPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(BrieflyTheme.primaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(BrieflyTheme.elevatedCard)
        .clipShape(Capsule())
    }
}

private struct BookFact: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(BrieflyTheme.secondaryText)

            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct BookActionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 15, weight: .heavy))
        .foregroundStyle(BrieflyTheme.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(BrieflyTheme.cardBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
    }
}

private struct ReadingStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.86))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(BrieflyTheme.elevatedCard.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct ReadingIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
                .frame(width: 42, height: 38)
                .background(BrieflyTheme.elevatedCard)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ReadingGoalEditor: View {
    let goalMinutes: Int
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftGoal: Int

    init(goalMinutes: Int, onSave: @escaping (Int) -> Void) {
        self.goalMinutes = goalMinutes
        self.onSave = onSave
        _draftGoal = State(initialValue: goalMinutes)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(BrieflyTheme.secondaryText.opacity(0.5))
                    .frame(width: 46, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 18)

                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .center) {
                        Text("Reading Goal")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(BrieflyTheme.secondaryText)
                                .frame(width: 38, height: 38)
                                .background(BrieflyTheme.elevatedCard.opacity(0.88))
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .stroke(BrieflyTheme.divider.opacity(0.74), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close reading goal")
                    }

                    targetControl

                    presetRow

                    Button {
                        onSave(draftGoal)
                        dismiss()
                    } label: {
                        Text("Save Goal")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(BrieflyTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrieflyTheme.actionGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(BrieflyTheme.backgroundBase)
                    .overlay {
                        LinearGradient(
                            colors: [
                                BrieflyTheme.accent.opacity(0.24),
                                BrieflyTheme.accentBlue.opacity(0.12),
                                BrieflyTheme.backgroundBase.opacity(0.98)
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(BrieflyTheme.divider.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.48), radius: 30, x: 0, y: -12)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .ignoresSafeArea()
    }

    private var targetControl: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily target")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.secondaryText.opacity(0.9))
                    .textCase(.uppercase)

                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text("\(draftGoal)")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.primaryText)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("min")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(BrieflyTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button {
                    draftGoal = max(5, draftGoal - 5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 17, weight: .heavy))
                        .frame(width: 48, height: 44)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(BrieflyTheme.divider)

                Button {
                    draftGoal = min(240, draftGoal + 5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .heavy))
                        .frame(width: 48, height: 44)
                }
            }
            .foregroundStyle(BrieflyTheme.primaryText)
            .background(BrieflyTheme.elevatedCard.opacity(0.9))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(BrieflyTheme.divider.opacity(0.68), lineWidth: 1)
            }
        }
        .padding(16)
        .background(BrieflyTheme.cardBase.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.78), lineWidth: 1)
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                let isSelected = draftGoal == minutes

                Button {
                    draftGoal = minutes
                } label: {
                    Text("\(minutes)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(isSelected ? BrieflyTheme.primaryText : BrieflyTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isSelected ? BrieflyTheme.accent.opacity(0.28) : BrieflyTheme.elevatedCard.opacity(0.82))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(isSelected ? BrieflyTheme.accent.opacity(0.5) : BrieflyTheme.divider.opacity(0.65), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BooksLoadingCard: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.16))
                    .frame(width: 58, height: 58)

                ProgressView()
                    .tint(BrieflyTheme.primaryText)
            }

            Text("Finding books")
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)

            Text("Loading titles, previews, and reading metadata.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.96))
                .overlay {
                    BrieflyTheme.surfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
        }
    }
}

private struct BooksEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.accent.opacity(0.16))
                    .frame(width: 58, height: 58)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 27, weight: .heavy))
                    .foregroundStyle(BrieflyTheme.accent)
            }

            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(BrieflyTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BrieflyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(BrieflyTheme.cardBase.opacity(0.96))
                .overlay {
                    BrieflyTheme.surfaceGradient
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BrieflyTheme.divider.opacity(0.86), lineWidth: 1)
        }
    }
}

#Preview {
    BooksView()
}
