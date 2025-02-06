import SwiftUI
import AVKit
import FirebaseFirestore
import Combine

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if viewModel.videos.isEmpty {
                    VStack {
                        Text("No videos available")
                            .foregroundColor(.white)
                        Button("Retry") {
                            viewModel.loadInitialVideos()
                        }
                        .foregroundColor(.blue)
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
                        AppLogger.debug("Video feed index changed to \(newIndex)")
                        viewModel.handleIndexChange(newIndex)
                    }
                }
            }
        }
        .ignoresSafeArea()
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
        AppLogger.debug("Initializing VideoFeedViewModel")
        loadInitialVideos()
    }
    
    func handleIndexChange(_ newIndex: Int) {
        AppLogger.debug("Handling index change to \(newIndex)")
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
        AppLogger.dbQuery("Loading initial batch of videos", collection: "videos")
        isLoading = true
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .snapshotPublisher()
            .map { querySnapshot -> [Video] in
                AppLogger.dbSuccess("Received \(querySnapshot.documents.count) videos", collection: "videos")
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
                            mediaUrl: video.mediaUrl,
                            createdAt: video.createdAt,
                            updatedAt: video.updatedAt,
                            engagement: video.engagement
                        )
                    } catch {
                        AppLogger.dbError("Error decoding video document", error: error, collection: "videos")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    AppLogger.dbError("Error loading videos", error: error, collection: "videos")
                }
            } receiveValue: { [weak self] videos in
                guard let self = self else { return }
                self.videos = videos
                self.isLoading = false
                AppLogger.dbSuccess("Successfully loaded \(videos.count) videos", collection: "videos")
                
                // Preload first few videos
                if !videos.isEmpty {
                    self.preloadVideosAround(index: 0)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadMoreVideos() {
        guard let lastSnapshot = lastDocumentSnapshot else {
            AppLogger.debug("No more videos to load (no last snapshot)")
            return
        }
        
        AppLogger.dbQuery("Loading more videos", collection: "videos")
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .start(afterDocument: lastSnapshot)
            .snapshotPublisher()
            .map { querySnapshot -> [Video] in
                AppLogger.dbSuccess("Received \(querySnapshot.documents.count) additional videos", collection: "videos")
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
                            mediaUrl: video.mediaUrl,
                            createdAt: video.createdAt,
                            updatedAt: video.updatedAt,
                            engagement: video.engagement
                        )
                    } catch {
                        AppLogger.dbError("Error decoding video document", error: error, collection: "videos")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    AppLogger.dbError("Error loading more videos", error: error, collection: "videos")
                }
            } receiveValue: { [weak self] newVideos in
                guard let self = self else { return }
                self.videos.append(contentsOf: newVideos)
                AppLogger.dbSuccess("Successfully loaded \(newVideos.count) additional videos", collection: "videos")
                
                // Preload videos around current index
                self.preloadVideosAround(index: self.currentIndex)
            }
            .store(in: &cancellables)
    }
    
    private func preloadVideosAround(index: Int) {
        AppLogger.debug("Preloading videos around index \(index)")
        let start = max(0, index - preloadWindow)
        let end = min(videos.count - 1, index + preloadWindow)
        
        // Clear out old preloaded videos
        let activeRange = Set(start...end)
        preloadedPlayers = preloadedPlayers.filter { activeRange.contains($0.key.hashValue) }
        
        // Preload videos in range
        for i in start...end {
            let video = videos[i]
            if preloadedPlayers[video.id] == nil {
                preloadVideo(video)
            }
        }
    }
    
    private func preloadVideo(_ video: Video) {
        AppLogger.debug("Preloading video: \(video.id)")
        guard let videoURL = URL(string: video.mediaUrl) else {
            AppLogger.debug("Invalid video URL for video: \(video.id)")
            return
        }
        
        Task {
            do {
                let asset = AVURLAsset(url: videoURL)
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 2.0
                
                let player = AVPlayer(playerItem: playerItem)
                
                // Preload the asset
                try await asset.load(.isPlayable)
                
                await MainActor.run {
                    preloadedPlayers[video.id] = player
                    AppLogger.debug("Successfully preloaded video: \(video.id)")
                }
            } catch {
                AppLogger.debug("Failed to preload video \(video.id): \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 