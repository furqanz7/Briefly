import SwiftUI

@MainActor
final class ThemeManager: ObservableObject {
    @Published var isNight: Bool = true
    @Published var colorScheme: ColorScheme = .dark
}
