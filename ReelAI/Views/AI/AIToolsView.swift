import SwiftUI

struct AIToolsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedTool: AITool?
    
    enum AITool: String, CaseIterable {
        case storyMaker = "Story Maker"
        case clipMaker = "Clip Maker"
        case audioMaker = "Audio Maker"
        case assembler = "Assembler"
        case publisher = "Publisher"
        
        var icon: String {
            switch self {
            case .storyMaker: return "text.book.closed"
            case .clipMaker: return "video"
            case .audioMaker: return "waveform"
            case .assembler: return "square.stack.3d.up"
            case .publisher: return "square.and.arrow.up"
            }
        }
        
        var description: String {
            switch self {
            case .storyMaker: return "Generate creative story ideas and scripts"
            case .clipMaker: return "Create AI-generated video clips"
            case .audioMaker: return "Generate custom audio and music"
            case .assembler: return "Combine media into final content"
            case .publisher: return "Upload and share your content"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Starfield background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
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
            )
            .ignoresSafeArea()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 20) {
                    ForEach(AITool.allCases, id: \.self) { tool in
                        NavigationLink {
                            destinationView(for: tool)
                        } label: {
                            AIToolCard(tool: tool)
                                .onTapGesture {
                                    Log.p(Log.app, Log.event, "User selected AI tool: \(tool.rawValue)")
                                }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            Log.p(Log.app, Log.start, "AI Tools view appeared")
        }
        .onDisappear {
            Log.p(Log.app, Log.exit, "AI Tools view disappeared")
        }
    }
    
    @ViewBuilder
    private func destinationView(for tool: AITool) -> some View {
        switch tool {
        case .publisher:
            PublishingView()
        default:
            ComingSoonView(feature: tool.rawValue)
                .onAppear {
                    Log.p(Log.app, Log.event, "Showing coming soon view for: \(tool.rawValue)")
                }
        }
    }
}

struct AIToolCard: View {
    let tool: AIToolsView.AITool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 30))
                .foregroundColor(.white)
            
            Text(tool.rawValue)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(tool.description)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

struct ComingSoonView: View {
    let feature: String
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                
                Text("\(feature) Coming Soon")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("We're working hard to bring you this feature.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            Log.p(Log.app, Log.start, "Coming soon view appeared for: \(feature)")
        }
        .onDisappear {
            Log.p(Log.app, Log.exit, "Coming soon view disappeared for: \(feature)")
        }
    }
}

#Preview {
    AIToolsView()
        .environmentObject(AuthenticationService.preview)
} 