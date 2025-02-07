import SwiftUI
import AVKit
import FirebaseFirestore
import Combine
import FirebaseStorage

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading videos...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                } else if viewModel.videos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        Text("Unable to load videos")
                            .foregroundColor(.white)
                        Text("Please check your internet connection")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Button("Retry") {
                            Log.p(Log.video, Log.event, "User tapped retry in feed")
                            viewModel.loadInitialVideos()
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 8)
                    }
                } else if !viewModel.isFirstVideoReady {
                    // Show loading state until first video is ready
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Preparing video playback...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                } else {
                    TabView(selection: $viewModel.currentIndex) {
                        ForEach(0..<(viewModel.videos.count + 1), id: \.self) { index in
                            if index == viewModel.videos.count {
                                // Dummy page: duplicate of the first video
                                if let firstVideo = viewModel.videos.first, let player = viewModel.getPlayer(for: firstVideo) {
                                    FeedVideoPlayerView(
                                        video: firstVideo,
                                        player: player,
                                        size: geometry.size
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .rotationEffect(.degrees(90))
                                    .tag(index)
                                    .onAppear {
                                        Log.p(Log.video, Log.event, "Reached dummy page, resetting feed to beginning")
                                        DispatchQueue.main.async {
                                            viewModel.currentIndex = 0
                                        }
                                    }
                                } else {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .rotationEffect(.degrees(90))
                                        .tag(index)
                                }
                            } else {
                                if let player = viewModel.getPlayer(for: viewModel.videos[index]) {
                                    FeedVideoPlayerView(
                                        video: viewModel.videos[index],
                                        player: player,
                                        size: geometry.size
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .rotationEffect(.degrees(90))
                                    .tag(index)
                                } else {
                                    // Show loading placeholder until player is ready
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .rotationEffect(.degrees(90))
                                        .tag(index)
                                }
                            }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(-90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .edgesIgnoringSafeArea(.all)  // Ensure full screen coverage
                    .onChange(of: viewModel.currentIndex) { newIndex in
                        Log.p(Log.video, Log.event, "Feed index changed to \(newIndex)")
                        viewModel.handleIndexChange(newIndex)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            Log.p(Log.video, Log.start, "Video feed view appeared")
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Video feed view disappeared")
        }
    }
}

class VideoFeedViewModel: ObservableObject {
    @Published private(set) var videos: [Video] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var isFirstVideoReady = false
    
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let preloadWindow = 4  // Increased from 3 to 4 to allow more aggressive preloading on fast swipes
    private let db = Firestore.firestore()
    private var lastDocumentSnapshot: DocumentSnapshot?
    private let batchSize = 10
    
    init() {
        Log.p(Log.video, Log.start, "Initializing video feed")
        loadInitialVideos()
    }
    
    func handleIndexChange(_ newIndex: Int) {
        Log.p(Log.video, Log.event, "Feed index changed to \(newIndex)")
        
        // Clean up players that are no longer needed
        cleanupInactivePlayers(around: newIndex)
        
        // If we're getting close to the end, load more videos
        if newIndex >= videos.count - preloadWindow {
            loadMoreVideos()
        }
        
        // Preload videos in window
        preloadVideosAround(index: newIndex)
    }
    
    func getPlayer(for video: Video) -> AVPlayer? {
        return preloadedPlayers[video.id]
    }
    
    func loadInitialVideos() {
        Log.p(Log.firebase, Log.read, "Loading initial batch of videos")
        isLoading = true
        videos = [] // Clear existing videos when reloading
        isFirstVideoReady = false // Reset first video ready state
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .snapshotPublisher()
            .timeout(.seconds(10), scheduler: DispatchQueue.main) // Add timeout
            .retry(2) // Add retry logic
            .map { querySnapshot -> [Video] in
                Log.p(Log.firebase, Log.read, "Received \(querySnapshot.documents.count) videos")
                self.lastDocumentSnapshot = querySnapshot.documents.last
                return querySnapshot.documents.compactMap { document in
                    do {
                        let video = try document.data(as: Video.self)
                        return Video(
                            id: document.documentID,
                            ownerId: video.ownerId,
                            username: video.username,
                            title: video.title,
                            description: video.description,
                            createdAt: video.createdAt,
                            updatedAt: video.updatedAt,
                            engagement: video.engagement
                        )
                    } catch {
                        Log.p(Log.firebase, Log.read, Log.error, "Failed to decode video: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoading = false
                if case .failure(let error) = completion {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to load videos: \(error.localizedDescription)")
                    // Videos array will remain empty, triggering error UI
                }
            } receiveValue: { [weak self] videos in
                guard let self = self else { return }
                self.videos = videos
                self.isLoading = false
                
                Log.p(Log.video, Log.event, "Loaded initial \(videos.count) videos")
                
                // Preload first few videos and set isFirstVideoReady when the first one is ready
                if !videos.isEmpty {
                    self.preloadVideosAround(index: 0)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadMoreVideos() {
        guard let lastSnapshot = lastDocumentSnapshot else {
            Log.p(Log.video, Log.event, "No more videos to load")
            return
        }
        
        Log.p(Log.firebase, Log.read, "Loading next batch of videos")
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .start(afterDocument: lastSnapshot)
            .snapshotPublisher()
            .map { querySnapshot -> [Video] in
                Log.p(Log.firebase, Log.read, "Received \(querySnapshot.documents.count) additional videos")
                self.lastDocumentSnapshot = querySnapshot.documents.last
                return querySnapshot.documents.compactMap { document in
                    do {
                        let video = try document.data(as: Video.self)
                        return Video(
                            id: document.documentID,
                            ownerId: video.ownerId,
                            username: video.username,
                            title: video.title,
                            description: video.description,
                            createdAt: video.createdAt,
                            updatedAt: video.updatedAt,
                            engagement: video.engagement
                        )
                    } catch {
                        Log.p(Log.firebase, Log.read, Log.error, "Failed to decode video: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to load more videos: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] newVideos in
                guard let self = self else { return }
                self.videos.append(contentsOf: newVideos)
                Log.p(Log.video, Log.event, "Added \(newVideos.count) more videos to feed")
                
                // Preload videos around current index
                self.preloadVideosAround(index: self.currentIndex)
            }
            .store(in: &cancellables)
    }
    
    private func preloadVideosAround(index: Int) {
        Log.p(Log.video, Log.event, "Preloading videos around index \(index)")
        let start = max(0, index - preloadWindow)
        let end = min(videos.count - 1, index + preloadWindow)
        
        // Keep a slightly larger buffer to prevent thrashing
        let bufferWindow = preloadWindow + 1
        let bufferStart = max(0, index - bufferWindow)
        let bufferEnd = min(videos.count - 1, index + bufferWindow)
        let activeIndices = Set(bufferStart...bufferEnd)
        let activeVideoIds = activeIndices.map { videos[$0].id }
        
        // Only remove players that are far from current index
        preloadedPlayers = preloadedPlayers.filter { videoId, _ in
            activeVideoIds.contains(videoId)
        }
        
        // Preload videos in range
        for i in start...end {
            let video = videos[i]
            if preloadedPlayers[video.id] == nil {
                preloadVideo(video)
            }
        }
    }
    
    private func preloadVideo(_ video: Video) {
        Log.p(Log.video, Log.event, "Preloading video: \(video.id)")
        
        // Don't reload if we already have a player
        if preloadedPlayers[video.id] != nil {
            Log.p(Log.video, Log.event, "Player already exists for video: \(video.id)")
            return
        }
        
        Task {
            do {
                // Get a reference to the video in Firebase Storage
                let storage = Storage.storage()
                let videoRef = storage.reference().child("videos/\(video.ownerId)/\(video.id).mp4")
                
                // Get the authenticated download URL
                let downloadURL = try await videoRef.downloadURL()
                Log.p(Log.video, Log.event, Log.success, "Got authenticated download URL for video: \(video.id)")
                
                let asset = AVURLAsset(url: downloadURL)
                
                // Load essential properties first
                try await asset.load(.isPlayable, .duration, .tracks)
                
                // Ensure video is playable
                guard asset.isPlayable else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
                }
                
                // Create player item with specific configuration
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 5.0  // Increased buffer
                
                // Create player with specific configuration
                let player = AVPlayer(playerItem: playerItem)
                player.automaticallyWaitsToMinimizeStalling = true
                player.preventsDisplaySleepDuringVideoPlayback = true
                
                // Set up player
                await MainActor.run {
                    // Clean up old player if it exists
                    if let oldPlayer = preloadedPlayers[video.id] {
                        oldPlayer.pause()
                        oldPlayer.replaceCurrentItem(with: nil)
                    }
                    
                    preloadedPlayers[video.id] = player
                    Log.p(Log.video, Log.event, Log.success, "Successfully preloaded video: \(video.id)")
                    
                    // If this is the first video and it's now ready, update the state
                    if !isFirstVideoReady && video.id == videos.first?.id {
                        isFirstVideoReady = true
                        Log.p(Log.video, Log.event, Log.success, "First video is ready for playback")
                    }
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Failed to preload video: \(error.localizedDescription)")
                // Clear the player on error
                await MainActor.run {
                    preloadedPlayers[video.id] = nil
                }
            }
        }
    }
    
    private func cleanupPlayer(for videoId: String) {
        if let player = preloadedPlayers[videoId] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers[videoId] = nil
            Log.p(Log.video, Log.event, "Cleaned up player for video: \(videoId)")
        }
    }
    
    private func cleanupInactivePlayers(around index: Int) {
        let activeIndices = Set((max(0, index - preloadWindow)...min(videos.count - 1, index + preloadWindow)))
        let activeVideoIds = Set(activeIndices.map { videos[$0].id })
        
        // Cleanup players that are no longer needed
        for (videoId, _) in preloadedPlayers {
            if !activeVideoIds.contains(videoId) {
                cleanupPlayer(for: videoId)
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 