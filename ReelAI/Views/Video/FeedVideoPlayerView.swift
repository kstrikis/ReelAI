import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class FeedVideoPlayerViewModel: ObservableObject {
    @Published private(set) var state = VideoState.loading
    @Published var showingControls = true
    @Published private(set) var hasUserReaction = false
    
    private let video: Video
    private(set) var player: AVPlayer?
    private var cancellables = Set<AnyCancellable>()
    private var setupTask: Task<Void, Never>?
    private var controlsTimer: Timer?
    private var statusObservation: AnyCancellable?
    private var bufferingObservation: AnyCancellable?
    
    enum VideoState: Equatable {
        case loading
        case buffering
        case playing
        case paused
        case failed(String)
        
        var isPlayable: Bool {
            switch self {
            case .playing, .paused, .buffering:
                return true
            case .loading, .failed:
                return false
            }
        }
    }
    
    init(video: Video, player: AVPlayer?) {
        Log.p(Log.video, Log.start, "Initializing player view model for video: \(video.id)")
        self.video = video
        setupPlayer(player)
        checkUserReaction()
        setupControlsTimer()
    }
    
    private func setupPlayer(_ player: AVPlayer?) {
        guard let player = player else {
            Log.p(Log.video, Log.event, Log.error, "Failed to initialize player - player was nil")
            state = .failed("Failed to initialize player")
            return
        }
        
        self.player = player
        
        // Cancel any existing setup
        setupTask?.cancel()
        statusObservation?.cancel()
        bufferingObservation?.cancel()
        
        setupTask = Task { @MainActor in
            guard let playerItem = player.currentItem else {
                Log.p(Log.video, Log.event, Log.error, "No player item available")
                state = .failed("No player item available")
                return
            }
            
            // Configure player
            player.automaticallyWaitsToMinimizeStalling = true
            
            do {
                // Load and verify asset
                let asset = playerItem.asset
                try await asset.load(.isPlayable, .tracks)
                
                guard asset.isPlayable else {
                    Log.p(Log.video, Log.event, Log.error, "Asset is not playable")
                    state = .failed("Video cannot be played")
                    return
                }
                
                // Load video tracks
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard !tracks.isEmpty else {
                    Log.p(Log.video, Log.event, Log.error, "No video tracks available")
                    state = .failed("No video tracks available")
                    return
                }
                
                // Ensure first track is loaded
                try await tracks[0].load(.timeRange)
                Log.p(Log.video, Log.event, Log.success, "Video track loaded successfully")
                
                // Set up status observation first
                statusObservation = playerItem.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        guard let self = self else { return }
                        switch status {
                        case .readyToPlay:
                            Log.p(Log.video, Log.event, Log.success, "Player ready to play")
                            if self.state == .loading {
                                self.state = .playing
                                player.play()
                            }
                        case .failed:
                            let error = playerItem.error?.localizedDescription ?? "Unknown error"
                            Log.p(Log.video, Log.event, Log.error, "Player failed: \(error)")
                            self.state = .failed(error)
                        default:
                            break
                        }
                    }
                
                // Only set up buffering observation after status is ready
                bufferingObservation = playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] isPlaybackLikelyToKeepUp in
                        guard let self = self else { return }
                        if !isPlaybackLikelyToKeepUp && self.state.isPlayable {
                            Log.p(Log.video, Log.event, "Player entered buffering state")
                            self.state = .buffering
                            player.pause()
                        } else if isPlaybackLikelyToKeepUp && self.state == .buffering {
                            Log.p(Log.video, Log.event, "Player resumed from buffering")
                            self.state = .playing
                            player.play()
                        }
                    }
                
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Player setup failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }
    
    private func setupControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                withAnimation {
                    self.showingControls = false
                }
            }
        }
    }
    
    func togglePlayback() {
        guard let player = player, state.isPlayable else { return }
        
        if state == .playing {
            Log.p(Log.video, Log.event, "Pausing playback")
            player.pause()
            state = .paused
        } else {
            Log.p(Log.video, Log.event, "Resuming playback")
            player.play()
            state = .playing
        }
    }
    
    private func checkUserReaction() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("reactions")
                    .whereField("userId", isEqualTo: userId)
                    .whereField("videoId", isEqualTo: video.id)
                    .getDocuments()
                
                await MainActor.run {
                    hasUserReaction = !snapshot.documents.isEmpty
                }
            } catch {
                Log.p(Log.video, Log.read, Log.error, "Failed to check reaction: \(error)")
            }
        }
    }
    
    func handleReaction(isLike: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let db = Firestore.firestore()
                let reactionData: [String: Any] = [
                    "userId": userId,
                    "videoId": video.id,
                    "isLike": isLike,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                try await db.collection("reactions").addDocument(data: reactionData)
                
                let updateData: [String: Any] = [
                    "engagement.\(isLike ? "likeCount" : "dislikeCount")": FieldValue.increment(Int64(1))
                ]
                
                try await db.collection("videos").document(video.id)
                    .updateData(updateData)
                
                await MainActor.run { hasUserReaction = true }
            } catch {
                Log.p(Log.video, Log.save, Log.error, "Failed to save reaction: \(error)")
            }
        }
    }
    
    deinit {
        Log.p(Log.video, Log.exit, "FeedVideoPlayerViewModel deinit")
        setupTask?.cancel()
        statusObservation?.cancel()
        bufferingObservation?.cancel()
        controlsTimer?.invalidate()
        cancellables.removeAll()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

struct FeedVideoPlayerView: View {
    let video: Video
    let size: CGSize
    @StateObject private var viewModel: FeedVideoPlayerViewModel
    
    init(video: Video, player: AVPlayer?, size: CGSize) {
        self.video = video
        self.size = size
        _viewModel = StateObject(wrappedValue: FeedVideoPlayerViewModel(video: video, player: player))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                case .playing:
                    if let player = viewModel.player {
                        CustomVideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .edgesIgnoringSafeArea(.all)
                    }
                case .failed(let error):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 40))
                        Text("Unable to load video")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text(error)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                case .buffering:
                    Text("Buffering...")
                        .foregroundColor(.white)
                        .font(.headline)
                case .paused:
                    Text("Paused")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                
                if viewModel.showingControls {
                    controlsOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .onTapGesture {
                withAnimation {
                    viewModel.showingControls.toggle()
                }
            }
        }
    }
    
    private var controlsOverlay: some View {
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
            
            HStack {
                Button(action: {
                    viewModel.togglePlayback()
                }) {
                    Image(systemName: viewModel.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                if !viewModel.hasUserReaction {
                    HStack(spacing: 20) {
                        Button(action: { viewModel.handleReaction(isLike: true) }) {
                            Image(systemName: "hand.thumbsup")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        Button(action: { viewModel.handleReaction(isLike: false) }) {
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