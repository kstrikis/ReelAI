import SwiftUI
import FirebaseFirestoreCombineSwift
import FirebaseFirestore
import Combine
import ReelAI  // Import the module containing our models

struct VideoListView: View {
    @StateObject private var viewModel = VideoListViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if viewModel.videos.isEmpty {
                VStack {
                    Text("No videos available")
                        .foregroundColor(.white)
                    Button("Retry") {
                        viewModel.loadVideos()
                    }
                    .foregroundColor(.blue)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.videos) { video in
                            VideoListItemView(video: video)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            viewModel.loadVideos()
        }
    }
}

struct VideoListItemView: View {
    let video: Video
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .foregroundColor(.white)
            
            Text(video.mediaUrl)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
            
            HStack {
                Text("By: \(video.username)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Spacer()
                
                // Display engagement metrics
                HStack(spacing: 12) {
                    Label("\(video.engagement.viewCount)", systemImage: "eye.fill")
                    Label("\(video.engagement.likeCount)", systemImage: "heart.fill")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

class VideoListViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    func loadVideos() {
        AppLogger.dbQuery("Loading videos from Firestore", collection: "videos")
        
        // Set loading state on main thread
        DispatchQueue.main.async {
            self.isLoading = true
            AppLogger.debug("Set isLoading to true")
        }
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .snapshotPublisher()
            .map { (querySnapshot: QuerySnapshot) -> [Video] in
                AppLogger.dbSuccess("Received \(querySnapshot.documents.count) videos", collection: "videos")
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
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                // Always reset loading state
                self.isLoading = false
                AppLogger.debug("Set isLoading to false")
                
                if case .failure(let error) = completion {
                    AppLogger.dbError("Error loading videos", error: error, collection: "videos")
                }
            }, receiveValue: { [weak self] videos in
                guard let self = self else { return }
                
                self.videos = videos
                // Ensure loading is false after setting videos
                self.isLoading = false
                AppLogger.debug("Set isLoading to false after receiving \(videos.count) videos")
                AppLogger.dbSuccess("Successfully loaded \(videos.count) videos", collection: "videos")
            })
            .store(in: &cancellables)
    }
}

#Preview {
    VideoListView()
} 