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
    
    enum VideoState {
        case loading
        case playing
        case failed
    }
    
    init(video: Video, player: AVPlayer?) {
        self.video = video
        setupPlayer(player)
        checkUserReaction()
        
        // Auto-hide controls
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
            withAnimation { showingControls = false }
        }
    }
    
    private func setupPlayer(_ player: AVPlayer?) {
        guard let player = player else {
            state = .failed
            return
        }
        
        self.player = player
        
        // ONE status observer
        player.currentItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.state = .playing
                    player.play()
                case .failed:
                    self.state = .failed
                default: break
                }
            }
            .store(in: &cancellables)
        
        // ONE loop observer
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .filter { [weak self] notification in
                guard let self = self,
                      let currentItem = self.player?.currentItem else { return false }
                return notification.object as? AVPlayerItem == currentItem
            }
            .sink { [weak self] _ in
                guard let self = self,
                      let player = self.player else { return }
                Task { @MainActor in
                    await player.seek(to: .zero)
                    player.play()
                }
            }
            .store(in: &cancellables)
    }
    
    func togglePlayback() {
        guard let player = player else { return }
        if state == .playing {
            player.pause()
            state = .loading
        } else {
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
        cancellables.removeAll()
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
                case .failed:
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 40))
                        Text("Unable to load video")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
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