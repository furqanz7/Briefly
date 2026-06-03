import SwiftUI

struct CircleIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(BrieflyTheme.elevatedCard)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle().stroke(BrieflyTheme.divider, lineWidth: 1)
                    }
                    .shadow(color: BrieflyTheme.glowBlue, radius: 10, x: 0, y: 0)

                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrieflyTheme.text(colorScheme).opacity(0.75))
            }
        }
    }
}
