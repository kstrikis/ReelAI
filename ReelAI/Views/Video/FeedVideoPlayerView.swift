import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth

struct FeedVideoPlayerView: View {
    let video: Video
    let player: AVPlayer?
    let size: CGSize
    
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
    }
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                VideoPlayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .onAppear {
                        player.play()
                        isPlaying = true
                        setupObservers(for: player)
                        checkUserReaction()
                    }
                    .onDisappear {
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
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        db.collection("videos")
            .document(video.id)
            .collection("reactions")
            .document(userId)
            .getDocument { snapshot, error in
                if let error = error {
                    AppLogger.dbError("Error checking user reaction", error: error, collection: "reactions")
                    return
                }
                
                if let data = snapshot?.data(),
                   let isLike = data["isLike"] as? Bool {
                    hasLiked = isLike
                    hasDisliked = !isLike
                }
            }
    }
    
    private func handleLike() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        if hasLiked {
            // Remove like
            removeReaction(userId: userId)
            localLikeCount -= 1
            hasLiked = false
        } else {
            // Add like
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
    
    private func setupObservers(for player: AVPlayer) {
        // Observe playback progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let currentTime = time.seconds
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration > 0 {
                progress = currentTime / duration
                self.duration = duration
            }
        }
        
        // Reset progress when item finishes playing
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
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