import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ConfettiOverlay: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { startConfetti() }
    }

    private func startConfetti() {
        particles = (0..<80).map { _ in
            ConfettiParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                color: [Color.red, .blue, .green, .yellow, .purple, .orange, .pink].randomElement()!,
                size: CGFloat.random(in: 6...12),
                opacity: 1.0
            )
        }

        for i in particles.indices {
            let delay = Double.random(in: 0...0.5)
            let targetY = CGFloat.random(in: 200...UIScreen.main.bounds.height + 100)
            let targetX = particles[i].position.x + CGFloat.random(in: -80...80)

            withAnimation(.easeOut(duration: Double.random(in: 1.5...2.5)).delay(delay)) {
                particles[i].position = CGPoint(x: targetX, y: targetY)
                particles[i].opacity = 0
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    var opacity: Double
}
