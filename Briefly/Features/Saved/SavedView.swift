import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SavedViewModel()
    @State private var selectedArticle: Article?
    @State private var isSearchVisible = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header

                    if appState.session != nil && isSearchVisible {
                        searchBar
                    }

                    if appState.session == nil {
                        AccountGateView(
                            title: "Sign in to save stories",
                            message: "Browse Briefly freely. Create an account only when you want bookmarks synced across devices.",
                            buttonTitle: "Sign In or Create Account"
                        )
                    } else {
                        content
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background {
                BrieflyTheme.premiumBackground
                    .ignoresSafeArea()
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.load(session: appState.session)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppNotifications.savedArticlesDidChange)) { _ in
                Task {
                    await viewModel.load(session: appState.session, force: true)
                }
            }
            .sheet(item: $selectedArticle) { article in
                ArticleDetailView(article: article, isSaved: true) {
                    await viewModel.remove(article: article, session: appState.session)
                }
            }
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Saved")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Spacer(minLength: 16)

            if appState.session != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchVisible.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(BrieflyTheme.elevatedCard)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
                            }

                        Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.45))

            TextField("Search saved articles", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(BrieflyTheme.text(colorScheme))
                .tint(BrieflyTheme.accent)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BrieflyTheme.elevatedCard)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BrieflyTheme.divider, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            SavedMessageCard(
                icon: "exclamationmark.triangle.fill",
                title: "Couldn’t load saved stories.",
                subtitle: errorMessage
            )
        } else if viewModel.isLoading && viewModel.articles.isEmpty {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    ArticleRowPlaceholder()
                }
            }
        } else if viewModel.filteredArticles.isEmpty {
            SavedMessageCard(
                icon: viewModel.searchText.isEmpty ? "bookmark" : "magnifyingglass.circle",
                title: viewModel.searchText.isEmpty ? "No saved stories yet." : "No saved stories match that search.",
                subtitle: viewModel.searchText.isEmpty ? "Bookmark articles from Home and they will appear here." : "Try a shorter keyword or clear the search."
            )
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.filteredArticles) { article in
                    Button {
                        selectedArticle = article
                    } label: {
                        ArticleRow(article: article, isSaved: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove Bookmark") {
                            Task {
                                await viewModel.remove(article: article, session: appState.session)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SavedMessageCard: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(BrieflyTheme.accent)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
