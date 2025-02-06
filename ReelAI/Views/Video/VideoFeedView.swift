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
                            Log.p(Log.video, Log.event, "User tapped retry in empty feed")
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
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: batchSize)
            .snapshotPublisher()
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
                            mediaUrl: video.mediaUrl,
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
                            mediaUrl: video.mediaUrl,
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
        Log.p(Log.video, Log.event, "Preloading video: \(video.id)")
        guard let videoURL = URL(string: video.mediaUrl) else {
            Log.p(Log.video, Log.event, Log.error, "Invalid video URL: \(video.mediaUrl)")
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
                    Log.p(Log.video, Log.event, Log.success, "Successfully preloaded video: \(video.id)")
                }
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Failed to preload video: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    VideoFeedView()
} 