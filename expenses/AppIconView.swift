import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.02, blue: 0.28),
                    Color(red: 0.0,  green: 0.20, blue: 0.42),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Card — credit-card proportions, slightly tilted
            ZStack {
                // Card body
                RoundedRectangle(cornerRadius: 60, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.42, blue: 1.0),
                                Color(red: 0.20, green: 0.45, blue: 0.95),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 700, height: 460)

                // Subtle sheen across the top half
                RoundedRectangle(cornerRadius: 60, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: 700, height: 460)

                // Currency symbol
                Text("$")
                    .font(.system(size: 310, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .rotationEffect(.degrees(-8))
            .offset(y: 30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 226, style: .continuous))
    }
}

#Preview("1024×1024") {
    AppIconView()
        .frame(width: 1024, height: 1024)
}
