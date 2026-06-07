import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            SportsView()
                .tabItem {
                    Label("Sports", systemImage: "sportscourt.fill")
                }
                .tag(AppTab.sports)

            JobsView()
                .tabItem {
                    Label("Jobs", systemImage: "briefcase.fill")
                }
                .tag(AppTab.jobs)

            BooksView()
                .tabItem {
                    Label("Books", systemImage: "books.vertical.fill")
                }
                .tag(AppTab.books)

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(AppTab.more)
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
        .tint(BrieflyTheme.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            appearance.backgroundColor = UIColor(BrieflyTheme.cardBase.opacity(0.72))
            appearance.shadowColor = UIColor(BrieflyTheme.divider.opacity(0.75))

            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.normal.iconColor = UIColor(BrieflyTheme.secondaryText.opacity(0.70))
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(BrieflyTheme.secondaryText.opacity(0.70)),
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = UIColor(BrieflyTheme.accent)
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(BrieflyTheme.primaryText),
                .font: UIFont.systemFont(ofSize: 11, weight: .heavy)
            ]
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            UITabBar.appearance().isTranslucent = true
        }
    }
}
