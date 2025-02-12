import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseStorage
import Combine

// MARK: - Vertical Video Feed System

@MainActor
class VerticalVideoHandler: ObservableObject {
    // Shared instance
    static let shared = VerticalVideoHandler()

    // Core data
    @Published var videos: [Video] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var isFirstVideoReady = false
    @Published private(set) var activeVideoIds: Set<String> = []
    @Published var isActive: Bool = false  // Track if this feed is currently visible
    private var isHandlingSwipe = false
    private var swipeHandlingTask: Task<Void, Never>?

    // Player management - simplified
    private var players: [String: AVPlayer] = [:]
    private var playerItemObservations: [String: AnyCancellable] = [:]
    private var readyToPlayStates: [String: Bool] = [:]
    private let playerSerializationQueue = DispatchQueue(label: "com.reelai.player.serialization")
    
    // Track video positions
    private var videoPositions: [String: CMTime] = [:]

    // Track active window size for video rendering
    private let activeWindowSize = 3 // Number of videos to keep active on each side of current
    private let preloadWindowSize = 2 // Number of videos to preload beyond active window
    
    // Track scroll progress for smooth audio transitions
    @Published private var scrollProgress: CGFloat = 0
    
    private init() {
        // Ensure we start inactive
        isActive = false
        loadInitialVideos()
    }

    func loadInitialVideos() {
        Log.p(Log.video, Log.event, "Loading initial batch of random videos")
        isLoading = true
        
        Task {
            do {
                let initialCheck = try await FirestoreService.shared.fetchVideoBatch(startingAfter: nil, limit: 1)
                if initialCheck.isEmpty {
                    Log.p(Log.video, Log.event, "No videos found, attempting to seed...")
                    try await FirestoreService.shared.seedVideos()
                }

                let batch = try await FirestoreService.shared.fetchRandomVideos(count: 5)
                Log.p(Log.video, Log.event, "Received \(batch.count) random videos")

                await MainActor.run {
                    self.videos = batch
                    self.isLoading = false
                    self.isFirstVideoReady = !batch.isEmpty
                    if !batch.isEmpty {
                        // Prepare initial set of videos
                        for i in 0..<min(3, batch.count) {
                            self.preparePlayer(for: batch[i])
                        }
                    }
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Initial load failed: \(error)")
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func preparePlayer(for video: Video) {
        // Don't prepare if we already have this player
        guard players[video.id] == nil else { return }
        
        Task {
            do {
                guard let url = try await FirestoreService.shared.getVideoDownloadURL(videoId: video.id) else {
                    Log.p(Log.video, Log.event, Log.error, "Failed to get download URL")
                    return
                }

                let asset = AVURLAsset(url: url)
                
                // Load essential properties using modern async API
                _ = try await asset.load(.tracks)
                _ = try await asset.load(.duration)
                
                // Configure player item with loaded asset
                let playerItem = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: playerItem)
                
                // Basic configuration for smooth playback
                player.automaticallyWaitsToMinimizeStalling = false
                player.volume = 0  // Start muted, will unmute when current
                
                // Set up looping
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { [weak player] _ in
                    player?.seek(to: .zero)
                    // Only auto-play if we're active
                    if self.isActive {
                        player?.play()
                    }
                }
                
                // Observe player item status
                let statusObservation = playerItem.publisher(for: \.status)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        guard let self = self else { return }
                        switch status {
                        case .readyToPlay:
                            self.readyToPlayStates[video.id] = true
                            // Only start playing if we're active and this is the current video
                            if self.isActive && video.id == self.videos[self.currentIndex].id {
                                player.volume = 1
                                player.play()
                            }
                        case .failed:
                            Log.p(Log.video, Log.event, Log.error, "Player item failed: \(String(describing: playerItem.error))")
                            self.readyToPlayStates[video.id] = false
                        default:
                            break
                        }
                    }
                
                await MainActor.run {
                    self.players[video.id] = player
                    self.playerItemObservations[video.id] = statusObservation
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Player preparation failed: \(error)")
            }
        }
    }

    func getPlayer(for video: Video) -> AVPlayer? {
        if let player = players[video.id] {
            return player
        }
        
        // If we don't have a player, prepare one if it's within our preload window
        if let currentIdx = videos.firstIndex(where: { $0.id == video.id }),
           abs(currentIdx - currentIndex) <= (activeWindowSize + preloadWindowSize) {
            preparePlayer(for: video)
        }
        
        return nil
    }

    func setActive(_ active: Bool) {
        isActive = active
        playerSerializationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If becoming inactive, pause all players
            if !active {
                for (_, player) in self.players {
                    if player.isPlaying {
                        player.pause()
                    }
                    player.volume = 0
                }
            } else if let currentVideo = self.videos.indices.contains(self.currentIndex) ? self.videos[self.currentIndex] : nil,
                      let currentPlayer = self.players[currentVideo.id],
                      self.readyToPlayStates[currentVideo.id] == true {
                // If becoming active, only play current video
                currentPlayer.volume = 1
                currentPlayer.playImmediately(atRate: 1.0)
            }
        }
    }

    func updateScrollProgress(_ progress: CGFloat) {
        // Don't process scroll updates when inactive
        guard isActive else { return }
        
        scrollProgress = progress
        
        // Get the relevant video indices based on scroll direction
        let currentVideoId = videos.indices.contains(currentIndex) ? videos[currentIndex].id : nil
        let nextVideoId = progress > 0 && videos.indices.contains(currentIndex + 1) ? videos[currentIndex + 1].id : nil
        let prevVideoId = progress < 0 && videos.indices.contains(currentIndex - 1) ? videos[currentIndex - 1].id : nil
        
        // Serialize playback state changes
        playerSerializationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update playback states and volumes
            for (videoId, player) in self.players {
                if videoId == currentVideoId {
                    // Current video
                    player.volume = Float(1 - abs(progress))
                    if !player.isPlaying && self.readyToPlayStates[videoId] == true {
                        player.playImmediately(atRate: 1.0)
                    }
                } else if videoId == nextVideoId && progress > 0 {
                    // Next video during downward scroll
                    player.volume = Float(progress)
                    if !player.isPlaying && self.readyToPlayStates[videoId] == true {
                        player.playImmediately(atRate: 1.0)
                    }
                } else if videoId == prevVideoId && progress < 0 {
                    // Previous video during upward scroll
                    player.volume = Float(-progress)
                    if !player.isPlaying && self.readyToPlayStates[videoId] == true {
                        player.playImmediately(atRate: 1.0)
                    }
                } else {
                    // Any other video should be paused
                    if player.isPlaying {
                        player.pause()
                        player.seek(to: .zero)
                    }
                    player.volume = 0
                }
            }
        }
    }

    func handleIndexChange(_ newIndex: Int) {
        // Don't process index changes when inactive
        guard isActive else { return }
        
        guard newIndex >= 0 && newIndex < videos.count else { return }
        
        let oldIndex = currentIndex
        currentIndex = newIndex
        
        // Serialize playback state changes
        playerSerializationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Handle playback states
            for (videoId, player) in self.players {
                if videoId == self.videos[newIndex].id {
                    // New current video
                    if self.readyToPlayStates[videoId] == true {
                        player.volume = 1
                        player.playImmediately(atRate: 1.0)
                    }
                } else if videoId == self.videos[oldIndex].id {
                    // Previous current video
                    if player.isPlaying {
                        player.pause()
                        player.seek(to: .zero)
                    }
                    player.volume = 0
                } else {
                    // Any other video
                    if player.isPlaying {
                        player.pause()
                        player.seek(to: .zero)
                    }
                    player.volume = 0
                }
            }
        }
        
        // Still preload videos even when inactive to ensure smooth transitions
        let newVideo = videos[newIndex]
        if players[newVideo.id] == nil {
            preparePlayer(for: newVideo)
        }
        
        // Preload videos in the preload window
        let preloadStart = max(0, newIndex - (activeWindowSize + preloadWindowSize))
        let preloadEnd = min(videos.count - 1, newIndex + (activeWindowSize + preloadWindowSize))
        
        for i in preloadStart...preloadEnd {
            preparePlayer(for: videos[i])
        }
        
        // Clean up players that are too far away
        cleanupDistantPlayers()
    }
    
    private func cleanupDistantPlayers() {
        playerSerializationQueue.async { [weak self] in
            guard let self = self else { return }
            
            for (videoId, player) in self.players {
                guard let index = self.videos.firstIndex(where: { $0.id == videoId }),
                      abs(index - self.currentIndex) > (self.activeWindowSize + self.preloadWindowSize) else { continue }
                
                if player.isPlaying {
                    player.pause()
                }
                player.replaceCurrentItem(with: nil)
                self.players.removeValue(forKey: videoId)
                self.playerItemObservations.removeValue(forKey: videoId)
                self.readyToPlayStates.removeValue(forKey: videoId)
            }
        }
    }

    func updateActiveVideos(_ videoId: String) {
        activeVideoIds.insert(videoId)
    }

    func updateVideoPosition(for videoId: String, position: CMTime) {
        videoPositions[videoId] = position
    }

    func isActiveIndex(_ index: Int) -> Bool {
        let activeRange = max(0, currentIndex - activeWindowSize)...min(videos.count - 1, currentIndex + activeWindowSize)
        Log.p(Log.video, Log.event, "Checking if index \(index) is active. Current index: \(currentIndex), Active range: \(activeRange)")
        return activeRange.contains(index)
    }
}

struct VideoVerticalFeed: View {
    @StateObject private var handler = VerticalVideoHandler.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragOffset = CGSize.zero
    @State private var dragDirection: DragDirection = .none
    @State private var scrollPositionThreshold = 1 // Minimum index change required to trigger update
    @Environment(\.dismiss) private var dismiss
    
    private enum DragDirection {
        case horizontal, vertical, none
    }
    
    var body: some View {
        let fullScreenSize = UIScreen.main.bounds.size
        
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if handler.videos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(handler.videos.indices, id: \.self) { index in
                                VideoVerticalPlayer(
                                    video: handler.videos[index],
                                    player: handler.getPlayer(for: handler.videos[index]),
                                    size: fullScreenSize
                                )
                                .id(handler.videos[index].id)
                                .frame(width: fullScreenSize.width, height: fullScreenSize.height)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: .init(
                        get: {
                            handler.videos.indices.contains(handler.currentIndex) ? handler.videos[handler.currentIndex].id : nil
                        },
                        set: { newPosition in
                            guard let newPosition = newPosition,
                                  let newIndex = handler.videos.firstIndex(where: { $0.id == newPosition }) else {
                                return
                            }
                            
                            // Only trigger handleIndexChange if the change exceeds the threshold
                            if abs(newIndex - handler.currentIndex) >= scrollPositionThreshold {
                                handler.handleIndexChange(newIndex)
                            }
                        }
                    ))
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                let progress = value.translation.height / fullScreenSize.height
                                handler.updateScrollProgress(-progress) // Invert because scroll up means next video
                            }
                            .onEnded { _ in
                                handler.updateScrollProgress(0)
                            }
                    )
                    .scrollDisabled(dragDirection == .horizontal)
                }
            }
        }
        .frame(width: fullScreenSize.width, height: fullScreenSize.height)
        .ignoresSafeArea()
        .onAppear {
            Log.p(Log.video, Log.start, "Vertical video feed appeared")
            handler.setActive(true)
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Vertical video feed disappeared")
            handler.setActive(false)
        }
        // Add scene phase handling
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                handler.setActive(false)
            case .active:
                // Only activate if we're actually visible
                // This prevents activation during TabView preloading
                if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                   let rootViewController = window.rootViewController,
                   rootViewController.view.subviews.contains(where: { $0.bounds.intersects(window.bounds) }) {
                    handler.setActive(true)
                }
            @unknown default:
                break
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            Text("No videos available")
                .foregroundColor(.white)
            Button("Retry") {
                handler.loadInitialVideos()
            }
            .foregroundColor(.blue)
        }
    }
}

struct VideoVerticalPlayer: View {
    let video: Video
    let player: AVPlayer?
    let size: CGSize
    
    var body: some View {
        ZStack {
            if let player = player {
                VerticalFeedVideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            } else {
                // Placeholder while video loads
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
            
            // Overlay controls and UI elements
            VStack {
                // Top controls (if any)
                Spacer()
                // Bottom controls (if any)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(0)
        }
        .frame(width: size.width, height: size.height)
        .clipped() // Ensure content doesn't overflow
        .background(Color.black)
    }
}

struct VerticalFeedVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        
        // Prevent the controller from trying to access transform properties
        if let playerLayer = controller.view.layer as? AVPlayerLayer {
            playerLayer.videoGravity = .resizeAspectFill
        }
        
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No updates needed
    }
}

// Add isPlaying extension for AVPlayer
private extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
} 