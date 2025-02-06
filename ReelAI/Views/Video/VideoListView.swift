import SwiftUI
import FirebaseFirestoreCombineSwift
import FirebaseFirestore
import Combine
import ReelAI

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
                        Log.p(Log.video, Log.event, "User tapped retry in empty video list")
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
            Log.p(Log.video, Log.start, "Video list view appeared")
            viewModel.loadVideos()
        }
        .onDisappear {
            Log.p(Log.video, Log.exit, "Video list view disappeared")
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
        .onAppear {
            Log.p(Log.video, Log.event, "Video list item appeared: \(video.id)")
        }
    }
}

class VideoListViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    
    func loadVideos() {
        Log.p(Log.firebase, Log.read, "Loading videos from Firestore")
        
        // Set loading state on main thread
        DispatchQueue.main.async {
            self.isLoading = true
            Log.p(Log.video, Log.event, "Set isLoading to true")
        }
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .snapshotPublisher()
            .map { (querySnapshot: QuerySnapshot) -> [Video] in
                Log.p(Log.firebase, Log.read, Log.success, "Received \(querySnapshot.documents.count) videos")
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
                        Log.p(Log.firebase, Log.read, Log.error, "Error decoding video document: \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                // Always reset loading state
                self.isLoading = false
                Log.p(Log.video, Log.event, "Set isLoading to false")
                
                if case .failure(let error) = completion {
                    Log.p(Log.firebase, Log.read, Log.error, "Error loading videos: \(error.localizedDescription)")
                }
            }, receiveValue: { [weak self] videos in
                guard let self = self else { return }
                
                self.videos = videos
                // Ensure loading is false after setting videos
                self.isLoading = false
                Log.p(Log.video, Log.event, "Set isLoading to false after receiving \(videos.count) videos")
                Log.p(Log.firebase, Log.read, Log.success, "Successfully loaded \(videos.count) videos")
            })
            .store(in: &cancellables)
    }
}

#Preview {
    VideoListView()
} 