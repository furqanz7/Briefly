import Foundation

@MainActor
final class ExplainLinkViewModel: ObservableObject {
    @Published var draftURL = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var result: ExplainedLink?

    private let service = ExplainLinkService()

    func explain() async {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Paste an article URL first."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            result = try await service.explain(urlString: trimmed)
            errorMessage = nil
            Haptics.success()
        } catch {
            result = nil
            errorMessage = "I couldn't explain that link clearly yet. Try a different article link or paste a simpler news page."
            Haptics.error()
        }
    }
}
