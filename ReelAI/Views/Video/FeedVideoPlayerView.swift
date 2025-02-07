import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine

// Move extensions to file scope
extension AVPlayer.TimeControlStatus {
    var statusDescription: String {
        switch self {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        @unknown default: return "unknown"
        }
    }
}

extension AVPlayerItem.Status {
    var statusDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }
}

@MainActor
class FeedVideoPlayerViewModel: ObservableObject {
    @Published var showingControls = true
    private let video: Video
    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    
    init(video: Video, player: AVPlayer?) {
        self.video = video
        self.player = player
        
        if let player = player {
            setupObservations(for: player)
        }
    }
    
    func updatePlayer(_ newPlayer: AVPlayer?) {
        Log.p(Log.video, Log.event, "🔄 Updating player for \(video.id)")
        self.player = newPlayer
        if let newPlayer = newPlayer {
            setupObservations(for: newPlayer)
        }
    }
    
    private func setupObservations(for player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player,
                  let duration = player.currentItem?.duration.seconds,
                  duration.isFinite else { return }
            
            let position = time.seconds
            let remaining = duration - position
            
            if remaining < 0.1 {
                Log.p(Log.video, Log.event, "⏳ End of video - looping")
                player.seek(to: .zero)
                player.play()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player = player else { return }
            Log.p(Log.video, Log.event, "🔄 End notification - looping")
            player.seek(to: .zero)
            player.play()
        }
    }
    
    func togglePlayback() {
        guard let player = player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

struct FeedVideoPlayerView: View {
    let video: Video
    let size: CGSize
    @StateObject private var playerController: FeedVideoPlayerViewModel
    
    init(video: Video, player: AVPlayer?, size: CGSize) {
        self.video = video
        self.size = size
        _playerController = StateObject(wrappedValue: FeedVideoPlayerViewModel(video: video, player: player))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let player = playerController.player {
                    CustomVideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .edgesIgnoringSafeArea(.all)
                }
                
                controlsOverlay
            }
            .onTapGesture {
                withAnimation {
                    if playerController.showingControls {
                        playerController.showingControls = false
                    } else {
                        playerController.togglePlayback()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        if playerController.showingControls {
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(video.username)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.7)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        
        // Disable all interaction except our custom controls
        controller.view.isUserInteractionEnabled = true
        for subview in controller.view.subviews {
            subview.isUserInteractionEnabled = false
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.view.frame = uiViewController.view.bounds
    }
}

#Preview {
    FeedVideoPlayerView(
        video: Video(
            id: "preview",
            ownerId: "user1",
            username: "demo_user",
            title: "Sample Video",
            description: "This is a sample video description that might be a bit longer to test the layout.",
            createdAt: Date(),
            updatedAt: Date(),
            engagement: Video.Engagement(
                viewCount: 1000,
                likeCount: 50,
                dislikeCount: 2,
                tags: ["funny": 30, "creative": 25]
            )
        ),
        player: nil,
        size: CGSize(width: 390, height: 844)
    )
} 