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
                        ForEach(0..<viewModel.videos.count, id: \.self) { index in
                            FeedVideoPlayerView(
                                video: viewModel.videos[index],
                                player: viewModel.getPlayer(for: viewModel.videos[index]),
                                size: geometry.size
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .rotationEffect(.degrees(90))
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(-90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .edgesIgnoringSafeArea(.all)
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
    private let preloadWindow = 2  // Reduced to 2 to minimize resource usage
    private let db = Firestore.firestore()
    private var lastDocumentSnapshot: DocumentSnapshot?
    private let batchSize = 5  // Reduced batch size for faster initial load
    private var preloadTasks: [String: Task<Void, Never>] = [:]  // Track preload tasks
    
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
        
        // Only preload the current video and the next one
        if newIndex < videos.count {
            preloadVideo(videos[newIndex])
            if newIndex + 1 < videos.count {
                preloadVideo(videos[newIndex + 1])
            }
        }
    }
    
    func getPlayer(for video: Video) -> AVPlayer? {
        return preloadedPlayers[video.id]
    }
    
    func loadInitialVideos() {
        Log.p(Log.firebase, Log.read, "Loading initial batch of videos")
        isLoading = true
        videos = [] // Clear existing videos when reloading
        isFirstVideoReady = false
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .snapshotPublisher()
            .timeout(.seconds(10), scheduler: DispatchQueue.main)
            .retry(2)
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
                }
            } receiveValue: { [weak self] videos in
                guard let self = self else { return }
                self.videos = videos
                Log.p(Log.video, Log.event, "Loaded initial \(videos.count) videos")
                
                // Only preload the first two videos
                if !videos.isEmpty {
                    self.preloadVideo(videos[0])
                    if videos.count > 1 {
                        self.preloadVideo(videos[1])
                    }
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
        // Don't reload if we already have a player
        if preloadedPlayers[video.id] != nil {
            Log.p(Log.video, Log.event, "Player already exists for video: \(video.id)")
            return
        }
        
        Log.p(Log.video, Log.event, "Preloading video: \(video.id)")
        
        // Cancel any existing preload task for this video
        preloadTasks[video.id]?.cancel()
        
        // Create new preload task
        let task = Task {
            do {
                // Get a reference to the video in Firebase Storage
                let storage = Storage.storage()
                let videoRef = storage.reference().child("videos/\(video.ownerId)/\(video.id).mp4")
                
                // Get the authenticated download URL
                let downloadURL = try await videoRef.downloadURL()
                Log.p(Log.video, Log.event, Log.success, "Got authenticated download URL for video: \(video.id)")
                
                let asset = AVURLAsset(url: downloadURL)
                
                // Load essential properties and transform
                try await asset.load(.isPlayable, .tracks)
                
                // Ensure video is playable
                guard asset.isPlayable else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
                }
                
                // Load video tracks
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard !tracks.isEmpty else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video tracks available"])
                }
                
                // Load track properties properly
                try await tracks[0].load(.naturalSize, .preferredTransform)
                
                // Create player item with specific configuration
                let playerItem = AVPlayerItem(asset: asset)
                
                // Create player with specific configuration
                let player = AVPlayer(playerItem: playerItem)
                player.automaticallyWaitsToMinimizeStalling = true
                
                if Task.isCancelled { return }
                
                // Set up player
                await MainActor.run {
                    // Clean up old player if it exists
                    cleanupPlayer(for: video.id)
                    
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
                    cleanupPlayer(for: video.id)
                }
            }
        }
        
        preloadTasks[video.id] = task
    }
    
    private func cleanupPlayer(for videoId: String) {
        if let player = preloadedPlayers[videoId] {
            player.pause()
            player.replaceCurrentItem(with: nil)
            preloadedPlayers[videoId] = nil
            Log.p(Log.video, Log.event, "Cleaned up player for video: \(videoId)")
        }
        // Cancel any ongoing preload task
        preloadTasks[videoId]?.cancel()
        preloadTasks[videoId] = nil
    }
    
    private func cleanupInactivePlayers(around index: Int) {
        // Only keep the current and next video players
        let activeVideoIds = Set([
            videos[index].id,
            index + 1 < videos.count ? videos[index + 1].id : ""
        ].filter { !$0.isEmpty })
        
        // Cleanup players that are no longer needed
        for (videoId, _) in preloadedPlayers {
            if !activeVideoIds.contains(videoId) {
                cleanupPlayer(for: videoId)
            }
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    deinit {
        Log.p(Log.video, Log.exit, "VideoFeedViewModel deinit")
        // Cancel all preload tasks
        for (_, task) in preloadTasks {
            task.cancel()
        }
        preloadTasks.removeAll()
        
        // Clean up all players
        for (videoId, _) in preloadedPlayers {
            cleanupPlayer(for: videoId)
        }
        preloadedPlayers.removeAll()
        cancellables.removeAll()
    }
}

#Preview {
    VideoFeedView()
} 