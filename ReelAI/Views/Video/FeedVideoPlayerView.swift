import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine

class VideoPlayerObserver: ObservableObject {
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let player: AVPlayer
    private let video: Video
    
    init(player: AVPlayer, video: Video) {
        self.player = player
        self.video = video
        setupObservers()
    }
    
    private func setupObservers() {
        // Monitor buffering state
        player.currentItem?.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { isLikelyToKeepUp in
                if isLikelyToKeepUp {
                    Log.p(Log.video, Log.event, nil, "Buffer sufficient for video: \(self.video.id)")
                } else {
                    Log.p(Log.video, Log.event, Log.warning, "Buffer depleted for video: \(self.video.id)")
                }
            }
            .store(in: &cancellables)
        
        // Monitor playback status
        player.currentItem?.publisher(for: \.status)
            .sink { status in
                switch status {
                case .readyToPlay:
                    Log.p(Log.video, Log.event, Log.success, "Video ready to play: \(self.video.id)")
                case .failed:
                    if let error = self.player.currentItem?.error {
                        Log.p(Log.video, Log.event, Log.error, "Playback failed: \(error.localizedDescription)")
                    }
                default:
                    Log.p(Log.video, Log.event, nil, "Playback status changed: \(status.rawValue)")
                }
            }
            .store(in: &cancellables)
        
        // Observe playback progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            let duration = self.player.currentItem?.duration.seconds ?? 0
            if duration > 0 {
                // Log only significant progress points
                if currentTime.truncatingRemainder(dividingBy: 5) < 0.5 { // Log every 5 seconds
                    Log.p(Log.video, Log.event, nil, "Playback at \(Int(currentTime))s/\(Int(duration))s")
                }
            }
        }
        
        // Monitor for playback stalls
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: player.currentItem)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Log.p(Log.video, Log.event, Log.warning, "Playback stalled: \(self.video.id)")
            }
            .store(in: &cancellables)
        
        // Monitor for playback completion
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
            .sink { [weak self] _ in
                guard let self = self else { return }
                Log.p(Log.video, Log.event, nil, "Video completed, looping: \(self.video.id)")
                self.player.seek(to: .zero)
                self.player.play()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }
}

struct FeedVideoPlayerView: View {
    let video: Video
    let player: AVPlayer?
    let size: CGSize
    
    @StateObject private var observer: VideoPlayerObserver
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var hasLiked = false
    @State private var hasDisliked = false
    @State private var localLikeCount: Int
    @State private var localDislikeCount: Int
    
    private let controlsTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let db = Firestore.firestore()
    
    init(video: Video, player: AVPlayer?, size: CGSize) {
        self.video = video
        self.player = player
        self.size = size
        _localLikeCount = State(initialValue: video.engagement.likeCount)
        _localDislikeCount = State(initialValue: video.engagement.dislikeCount)
        
        // Initialize observer with a dummy player if none provided
        if let player = player {
            _observer = StateObject(wrappedValue: VideoPlayerObserver(player: player, video: video))
        } else {
            // Create a dummy player that won't be used
            let dummyPlayer = AVPlayer()
            _observer = StateObject(wrappedValue: VideoPlayerObserver(player: dummyPlayer, video: video))
        }
        
        Log.p(Log.video, Log.event, "Initializing player view for video: \(video.id)")
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                VideoPlayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .onAppear {
                        Log.p(Log.video, Log.start, nil, "Starting playback for video: \(video.id)")
                        player.play()
                        isPlaying = true
                        checkUserReaction()
                    }
                    .onDisappear {
                        Log.p(Log.video, Log.stop, nil, "Stopping playback for video: \(video.id)")
                        player.pause()
                        isPlaying = false
                    }
                    .onTapGesture {
                        withAnimation {
                            showControls.toggle()
                        }
                    }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            
            // Video info and controls overlay
            if showControls {
                // Left side - Video info
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("@\(video.username)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        if let description = video.description {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        
                        // View count
                        Label("\(video.engagement.viewCount) views", systemImage: "eye.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Right side - Interaction buttons
                VStack(spacing: 20) {
                    Spacer()
                    
                    // Play/Pause
                    Button(action: {
                        isPlaying.toggle()
                        if isPlaying {
                            player?.play()
                        } else {
                            player?.pause()
                        }
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    // Like
                    VStack(spacing: 4) {
                        Button(action: { handleLike() }) {
                            Image(systemName: hasLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.title2)
                                .foregroundColor(hasLiked ? .blue : .white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        Text("\(localLikeCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    // Dislike
                    VStack(spacing: 4) {
                        Button(action: { handleDislike() }) {
                            Image(systemName: hasDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.title2)
                                .foregroundColor(hasDisliked ? .red : .white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        Text("\(localDislikeCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                        .frame(height: 60)
                }
                .padding(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onReceive(controlsTimer) { _ in
            if showControls {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
    
    private func checkUserReaction() {
        guard let userId = Auth.auth().currentUser?.uid else {
            Log.p(Log.firebase, Log.read, Log.warning, "No user ID available for reaction check")
            return
        }
        
        Log.p(Log.firebase, Log.read, nil, "Checking user reaction for video: \(video.id)")
        
        db.collection("videos")
            .document(video.id)
            .collection("reactions")
            .document(userId)
            .getDocument { snapshot, error in
                if let error = error {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to check reaction: \(error.localizedDescription)")
                    return
                }
                
                if let data = snapshot?.data(),
                   let isLike = data["isLike"] as? Bool {
                    Log.p(Log.firebase, Log.read, Log.success, "Found user reaction: \(isLike ? "like" : "dislike")")
                    hasLiked = isLike
                    hasDisliked = !isLike
                } else {
                    Log.p(Log.firebase, Log.read, nil, "No existing reaction found")
                }
            }
    }
    
    private func handleLike() {
        guard let userId = Auth.auth().currentUser?.uid else {
            Log.p(Log.firebase, Log.event, Log.warning, "No user ID available for like action")
            return
        }
        
        if hasLiked {
            Log.p(Log.firebase, Log.update, "Removing like from video: \(video.id)")
            removeReaction(userId: userId)
            localLikeCount -= 1
            hasLiked = false
        } else {
            Log.p(Log.firebase, Log.update, "Adding like to video: \(video.id)")
            if hasDisliked {
                localDislikeCount -= 1
            }
            addReaction(userId: userId, isLike: true)
            localLikeCount += 1
            hasLiked = true
            hasDisliked = false
        }
    }
    
    private func handleDislike() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        if hasDisliked {
            // Remove dislike
            removeReaction(userId: userId)
            localDislikeCount -= 1
            hasDisliked = false
        } else {
            // Add dislike
            if hasLiked {
                localLikeCount -= 1
            }
            addReaction(userId: userId, isLike: false)
            localDislikeCount += 1
            hasDisliked = true
            hasLiked = false
        }
    }
    
    private func addReaction(userId: String, isLike: Bool) {
        AppLogger.dbWrite("Adding \(isLike ? "like" : "dislike") reaction", collection: "reactions")
        
        let reactionData: [String: Any] = [
            "userId": userId,
            "isLike": isLike,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("videos")
            .document(video.id)
            .collection("reactions")
            .document(userId)
            .setData(reactionData) { error in
                if let error = error {
                    AppLogger.dbError("Error adding reaction", error: error, collection: "reactions")
                    return
                }
                AppLogger.dbSuccess("Successfully added reaction", collection: "reactions")
                
                // Update video engagement counts
                let engagementUpdate = [
                    "engagement.\(isLike ? "likeCount" : "dislikeCount")": FieldValue.increment(Int64(1)),
                    "engagement.\(!isLike ? "likeCount" : "dislikeCount")": FieldValue.increment(Int64(-1))
                ]
                
                db.collection("videos")
                    .document(video.id)
                    .updateData(engagementUpdate) { error in
                        if let error = error {
                            AppLogger.dbError("Error updating engagement counts", error: error, collection: "videos")
                        }
                    }
            }
    }
    
    private func removeReaction(userId: String) {
        AppLogger.dbDelete("Removing reaction", collection: "reactions")
        
        db.collection("videos")
            .document(video.id)
            .collection("reactions")
            .document(userId)
            .delete { error in
                if let error = error {
                    AppLogger.dbError("Error removing reaction", error: error, collection: "reactions")
                    return
                }
                AppLogger.dbSuccess("Successfully removed reaction", collection: "reactions")
                
                // Update video engagement counts
                let engagementUpdate = [
                    "engagement.\(hasLiked ? "likeCount" : "dislikeCount")": FieldValue.increment(Int64(-1))
                ]
                
                db.collection("videos")
                    .document(video.id)
                    .updateData(engagementUpdate) { error in
                        if let error = error {
                            AppLogger.dbError("Error updating engagement counts", error: error, collection: "videos")
                        }
                    }
            }
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
            mediaUrl: "https://example.com/video.mp4",
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