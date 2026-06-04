import SwiftUI

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 42
    var iconSize: CGFloat = 16
    var tint: Color = BrieflyTheme.primaryText.opacity(0.84)
    var isProminent = false
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isProminent ? tint.opacity(0.18) : BrieflyTheme.elevatedCard.opacity(0.96))
                    .frame(width: size, height: size)
                    .overlay {
                        Circle()
                            .stroke(isProminent ? tint.opacity(0.46) : BrieflyTheme.divider.opacity(0.92), lineWidth: 1)
                    }
                    .shadow(color: isProminent ? tint.opacity(0.18) : .black.opacity(0.16), radius: isProminent ? 18 : 10, x: 0, y: 6)

                if isLoading {
                    ProgressView()
                        .tint(tint)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: .heavy))
                        .foregroundStyle(tint)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
