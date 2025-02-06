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
                } else {
                    TabView(selection: $viewModel.currentIndex) {
                        ForEach(viewModel.videos.indices, id: \.self) { index in
                            FeedVideoPlayerView(
                                video: viewModel.videos[index],
                                player: viewModel.getPlayer(for: viewModel.videos[index]),
                                size: geometry.size
                            )
                            .rotationEffect(.degrees(90))
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(-90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
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
    
    private var preloadedPlayers: [String: AVPlayer] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let preloadWindow = 1 // Number of videos to preload in each direction
    
    private let db = Firestore.firestore()
    private var lastDocumentSnapshot: DocumentSnapshot?
    private let batchSize = 10
    
    init() {
        Log.p(Log.video, Log.start, "Initializing video feed")
        loadInitialVideos()
    }
    
    func handleIndexChange(_ newIndex: Int) {
        Log.p(Log.video, Log.event, "Feed index changed to \(newIndex)")
        // If we're getting close to the end, load more videos
        if newIndex >= videos.count - 3 {
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
                
                // Preload first few videos
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
        
        // Don't clear preloaded videos immediately
        // Instead, keep a buffer of videos around the current index
        let activeIndices = Set(start...end)
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
                playerItem.preferredForwardBufferDuration = 2.0
                
                // Create player with specific configuration
                let player = AVPlayer(playerItem: playerItem)
                player.automaticallyWaitsToMinimizeStalling = true
                player.preventsDisplaySleepDuringVideoPlayback = true
                
                // Set up player
                await MainActor.run {
                    preloadedPlayers[video.id] = player
                    Log.p(Log.video, Log.event, Log.success, "Successfully preloaded video: \(video.id)")
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
}

#Preview {
    VideoFeedView()
} 