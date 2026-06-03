import SwiftUI

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            SportsView()
                .tabItem {
                    Label("Sports", systemImage: "sportscourt.fill")
                }

            JobsView()
                .tabItem {
                    Label("Jobs", systemImage: "briefcase.fill")
                }

            BooksView()
                .tabItem {
                    Label("Books", systemImage: "books.vertical.fill")
                }

            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
        }
        .background {
            BrieflyTheme.premiumBackground
                .ignoresSafeArea()
        }
        .tint(BrieflyTheme.accent)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear

            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.normal.iconColor = UIColor(BrieflyTheme.secondaryText.opacity(0.72))
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(BrieflyTheme.secondaryText.opacity(0.72))]
            itemAppearance.selected.iconColor = UIColor(BrieflyTheme.accent)
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(BrieflyTheme.primaryText)]
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
