import SwiftUI

struct AskBrieflyView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasAcceptedAIConsent") private var hasAcceptedAIConsent = false
    @State private var isShowingAIInfo = false

    init(article: Article) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(article: article))
    }

    init(newsContext: String) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(newsContext: newsContext))
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(viewModel.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                Spacer()
                Button {
                    isShowingAIInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.68))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            Haptics.selection()
                            if hasAcceptedAIConsent {
                                Task { await viewModel.send(suggestion) }
                            } else {
                                isShowingAIInfo = true
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(BrieflyTheme.accent.opacity(0.18))
                        .overlay {
                            Capsule().stroke(BrieflyTheme.accent.opacity(0.32), lineWidth: 1)
                        }
                        .foregroundStyle(BrieflyTheme.accent)
                        .clipShape(Capsule())
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            HStack(alignment: .bottom, spacing: 8) {
                                if message.role == .assistant {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(BrieflyTheme.actionFill)
                                        .clipShape(Circle())
                                } else {
                                    Spacer(minLength: 36)
                                }

                                Text(message.text)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(message.role == .assistant ? BrieflyTheme.text(colorScheme) : Color.white)
                                    .padding(14)
                                    .background(message.role == .assistant ? BrieflyTheme.card(colorScheme) : BrieflyTheme.actionFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                if message.role == .user {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(BrieflyTheme.accent)
                                        .clipShape(Circle())
                                } else {
                                    Spacer(minLength: 36)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages) { _, newValue in
                    guard let lastID = newValue.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let lastID = viewModel.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Type your question...", text: $viewModel.draft)
                    .padding(14)
                    .background(BrieflyTheme.elevatedCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(BrieflyTheme.divider, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(BrieflyTheme.text(colorScheme))
                    .tint(BrieflyTheme.accent)
                    .submitLabel(.send)

                CircleIconButton(systemName: "mic.fill") {}
                CircleIconButton(systemName: viewModel.isSending ? "hourglass" : "arrow.up") {
                    Haptics.impact(.medium)
                    guard hasAcceptedAIConsent else {
                        isShowingAIInfo = true
                        return
                    }
                    Task {
                        await viewModel.send()
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .disabled(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
        .sheet(isPresented: $isShowingAIInfo) {
            AIPrivacySheet(
                providerName: AppConfig.shared.aiProviderDisplayName,
                hasAcceptedAIConsent: $hasAcceptedAIConsent
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if !hasAcceptedAIConsent {
                isShowingAIInfo = true
            }
        }
    }
}

private struct AIPrivacySheet: View {
    let providerName: String
    @Binding var hasAcceptedAIConsent: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AI Privacy")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(BrieflyTheme.text(colorScheme))

                    privacyBlock(
                        title: "What Briefly sends",
                        body: "Your Ask Briefly question and either the current article context or the latest in-app news context, depending on the mode you use."
                    )

                    privacyBlock(
                        title: "Third-party provider",
                        body: "This chat is powered by \(providerName). Briefly does not send your password or payment data to the AI provider."
                    )

                    privacyBlock(
                        title: "Where to review this later",
                        body: "Open Ask Briefly and tap the info button in the top right at any time."
                    )

                    privacyBlock(
                        title: "How messages are stored",
                        body: "Chat messages are shown only on this device during the current session. They are not synced across devices by Briefly."
                    )

                    Button {
                        hasAcceptedAIConsent = true
                        dismiss()
                    } label: {
                        Text("I Understand")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(BrieflyTheme.actionGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(BrieflyTheme.premiumBackground.ignoresSafeArea())
            .interactiveDismissDisabled(!hasAcceptedAIConsent)
        }
    }

    private func privacyBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BrieflyTheme.text(colorScheme))

            Text(body)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.72))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrieflyTheme.card(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
