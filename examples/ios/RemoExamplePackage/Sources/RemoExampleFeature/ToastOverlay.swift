import SwiftUI

struct ToastOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let message = store.toastMessage {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white.opacity(0.8))
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.9))
            .background(Color.accentColor.opacity(0.85))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
        }
    }
}
