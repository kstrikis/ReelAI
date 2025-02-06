import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine

struct FeedVideoPlayerView: View {
    let video: Video
    let player: AVPlayer?
    let size: CGSize
    
    @StateObject private var playerObserver: PlayerObserver
    @State private var showingControls = true
    @State private var isPlaying = false
    @State private var hasUserReaction = false
    
    init(video: Video, player: AVPlayer?, size: CGSize) {
        self.video = video
        self.player = player
        self.size = size
        _playerObserver = StateObject(wrappedValue: PlayerObserver(video: video, player: player))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .disabled(true)  // Disable default controls
                        .onAppear {
                            Log.p(Log.video, Log.event, "Starting playback for video: \(video.id)")
                            player.seek(to: .zero)
                            player.play()
                            isPlaying = true
                        }
                        .onDisappear {
                            Log.p(Log.video, Log.event, "Stopping playback for video: \(video.id)")
                            player.pause()
                            isPlaying = false
                        }
                } else {
                    // Show loading state
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                
                // Video controls overlay
                if showingControls {
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
                        
                        // Video controls
                        HStack {
                            Button(action: {
                                if isPlaying {
                                    player?.pause()
                                } else {
                                    player?.play()
                                }
                                isPlaying.toggle()
                            }) {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            // Like/dislike buttons
                            if !hasUserReaction {
                                HStack(spacing: 20) {
                                    Button(action: {
                                        handleReaction(isLike: true)
                                    }) {
                                        Image(systemName: "hand.thumbsup")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Button(action: {
                                        handleReaction(isLike: false)
                                    }) {
                                        Image(systemName: "hand.thumbsdown")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .padding()
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
            .onTapGesture {
                withAnimation {
                    showingControls.toggle()
                }
            }
        }
        .onAppear {
            // Check for existing reaction
            checkUserReaction()
            
            // Auto-hide controls after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showingControls = false
                }
            }
        }
    }
    
    private func checkUserReaction() {
        Task {
            do {
                let db = Firestore.firestore()
                if let userId = Auth.auth().currentUser?.uid {
                    let snapshot = try await db.collection("reactions")
                        .whereField("userId", isEqualTo: userId)
                        .whereField("videoId", isEqualTo: video.id)
                        .getDocuments()
                    
                    await MainActor.run {
                        hasUserReaction = !snapshot.documents.isEmpty
                    }
                }
            } catch {
                Log.p(Log.video, Log.read, Log.error, "Failed to check reaction: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleReaction(isLike: Bool) {
        Task {
            do {
                let db = Firestore.firestore()
                if let userId = Auth.auth().currentUser?.uid {
                    try await db.collection("reactions").addDocument(data: [
                        "userId": userId,
                        "videoId": video.id,
                        "isLike": isLike,
                        "createdAt": FieldValue.serverTimestamp()
                    ])
                    
                    // Update video engagement
                    let videoRef = db.collection("videos").document(video.id)
                    try await videoRef.updateData([
                        "engagement.\(isLike ? "likeCount" : "dislikeCount")": FieldValue.increment(Int64(1))
                    ])
                    
                    await MainActor.run {
                        hasUserReaction = true
                    }
                }
            } catch {
                Log.p(Log.video, Log.save, Log.error, "Failed to save reaction: \(error.localizedDescription)")
            }
        }
    }
}

class PlayerObserver: ObservableObject {
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init(video: Video, player: AVPlayer?) {
        Log.p(Log.video, Log.start, "Initializing player observer for video: \(video.id)")
        self.player = player
        setupObservers()
    }
    
    private func setupObservers() {
        Log.p(Log.video, Log.start, "Setting up video player observers")
        
        guard let player = player else {
            Log.p(Log.video, Log.event, Log.warning, "No player available for observation")
            return
        }
        
        // Monitor playback status
        player.currentItem?.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    Log.p(Log.video, Log.event, Log.success, "Video ready to play")
                case .failed:
                    if let error = player.currentItem?.error {
                        Log.p(Log.video, Log.event, Log.error, "Playback failed: \(error.localizedDescription)")
                    }
                default:
                    Log.p(Log.video, Log.event, "Playback status changed: \(status.rawValue)")
                }
            }
            .store(in: &cancellables)
        
        // Add periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            // Handle time updates if needed
        }
        
        Log.p(Log.video, Log.exit, "Video player observers setup complete")
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        cancellables.removeAll()
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