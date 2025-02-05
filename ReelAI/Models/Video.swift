import FirebaseFirestore
import Foundation

struct Video: Codable {
    @DocumentID var id: String?
    let userId: String
    let username: String
    let title: String
    let description: String?
    let rawVideoURL: String
    let processedVideoURL: String?
    @ServerTimestamp var createdAt: Date?
    let status: VideoStatus
    
    var shareURL: URL? {
        guard let id = id else { return nil }
        return URL(string: "https://reelai.example.com/@\(username)/\(id)")
    }
}

enum VideoStatus: String, Codable {
    case uploading
    case processing
    case ready
    case error
} 