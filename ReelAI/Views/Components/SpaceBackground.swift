import SwiftUI

struct SpaceBackground: View {
    // Deep space colors
    private let spaceBackground = Color(red: 0.1, green: 0.1, blue: 0.2)
    private let spaceAccent = Color(red: 0.15, green: 0.1, blue: 0.25)
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [spaceBackground, spaceAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Starfield effect
            ZStack {
                // Distant stars (small)
                ForEach(0..<100) { _ in
                    Circle()
                        .fill(.white.opacity(.random(in: 0.1...0.3)))
                        .frame(width: 1, height: 1)
                        .position(
                            x: .random(in: 0...UIScreen.main.bounds.width),
                            y: .random(in: 0...UIScreen.main.bounds.height)
                        )
                }
                // Mid-distance stars (medium)
                ForEach(0..<50) { _ in
                    Circle()
                        .fill(.white.opacity(.random(in: 0.3...0.5)))
                        .frame(width: 2, height: 2)
                        .position(
                            x: .random(in: 0...UIScreen.main.bounds.width),
                            y: .random(in: 0...UIScreen.main.bounds.height)
                        )
                }
                // Close stars (large)
                ForEach(0..<20) { _ in
                    Circle()
                        .fill(.white.opacity(.random(in: 0.5...0.7)))
                        .frame(width: 3, height: 3)
                        .position(
                            x: .random(in: 0...UIScreen.main.bounds.width),
                            y: .random(in: 0...UIScreen.main.bounds.height)
                        )
                }
            }
            .ignoresSafeArea()
        }
    }
}

// Extension to make it easy to add the background to any view
extension View {
    func spaceBackground() -> some View {
        self.background(SpaceBackground())
    }
}

#Preview {
    Text("Hello, Space!")
        .foregroundColor(.white)
        .spaceBackground()
} 