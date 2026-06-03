import SwiftUI

struct ExplainLinkView: View {
    @StateObject private var viewModel = ExplainLinkViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAskBriefly = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Explain Any Link")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(BrieflyTheme.text(colorScheme))

                        Text("Paste any news article link and Briefly will break it down in simple language.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.62))
                    }

                    VStack(spacing: 12) {
                        TextField("https://example.com/news-story", text: $viewModel.draftURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(BrieflyTheme.elevatedCard)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(BrieflyTheme.divider, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Button {
                            Task { await viewModel.explain() }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isLoading {
                                    ProgressView().tint(.white)
                                }
                                Text(viewModel.isLoading ? "Explaining..." : "Explain Link")
                            }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BrieflyTheme.actionGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoading)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    if let result = viewModel.result {
                        resultCard(title: "Simple Summary", body: result.summary)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Key Points")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(BrieflyTheme.text(colorScheme))

                            ForEach(result.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(BrieflyTheme.accent)
                                        .frame(width: 7, height: 7)
                                        .padding(.top, 7)
                                    Text(point)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(BrieflyTheme.text(colorScheme))
                                }
                            }
                        }
                        .padding(18)
                        .background(BrieflyTheme.card(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        resultCard(title: "Why It Matters", body: result.whyItMatters)

                        Button {
                            showAskBriefly = true
                        } label: {
                            Text("Ask Briefly About This Link")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(BrieflyTheme.actionGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAskBriefly) {
                if let result = viewModel.result {
                    AskBrieflyView(article: result.articleProxy)
                }
            }
        }
    }

    private func resultCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
