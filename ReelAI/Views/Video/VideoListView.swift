import SwiftUI
import FirebaseFirestoreCombineSwift
import Combine

struct VideoListView: View {
    @StateObject private var viewModel = VideoListViewModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
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
        AppLogger.methodEntry(AppLogger.ui, "Loading videos from Firestore")
        isLoading = true
        
        db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .publisher()
            .map { querySnapshot -> [Video] in
                AppLogger.info(AppLogger.ui, "Received \(querySnapshot.documents.count) videos from Firestore")
                return querySnapshot.documents.compactMap { document in
                    do {
                        var video = try document.data(as: Video.self)
                        video.id = document.documentID
                        return video
                    } catch {
                        AppLogger.error(AppLogger.ui, "Error decoding video document: \(error)")
                        return nil
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoading = false
                if case .failure(let error) = completion {
                    AppLogger.error(AppLogger.ui, "Error loading videos: \(error)")
                }
            } receiveValue: { videos in
                self.videos = videos
                AppLogger.methodExit(AppLogger.ui, "Successfully loaded \(videos.count) videos")
            }
            .store(in: &cancellables)
    }
}

// Video model matching our Firestore schema
struct Video: Codable, Identifiable {
    var id: String?
    let ownerId: String
    let username: String
    let title: String
    let description: String?
    let mediaUrl: String
    let createdAt: Date
    let updatedAt: Date
    let engagement: Engagement
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId
        case username
        case title
        case description
        case mediaUrl
        case createdAt
        case updatedAt
        case engagement
    }
}

struct Engagement: Codable {
    let viewCount: Int
    let likeCount: Int
    let dislikeCount: Int
    let tags: [String: Int]
    
    static var empty: Engagement {
        Engagement(viewCount: 0, likeCount: 0, dislikeCount: 0, tags: [:])
    }
}

#Preview {
    VideoListView()
} 