import FirebaseFirestore
import Foundation

public struct Video: Identifiable, Codable {
    public let id: String
    public let ownerId: String
    public let username: String
    public let title: String
    public let description: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let engagement: Engagement
    public let random: Int?  // Random value for video ordering, optional for backward compatibility
    
    public init(
        id: String,
        ownerId: String,
        username: String,
        title: String,
        description: String?,
        createdAt: Date,
        updatedAt: Date,
        engagement: Engagement,
        random: Int? = nil  // Make random parameter optional with default value
    ) {
        self.id = id
        self.ownerId = ownerId
        self.username = username
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.engagement = engagement
        self.random = random
    }
    
    // Add computed property for file path
    public var filePath: String {
        return "videos/\(ownerId)/\(id).mp4"
    }
    
    public var computedMediaUrl: String {
        let bucket = "reelai-53f8b.firebasestorage.app"
        let path = "videos/\(ownerId)/\(id).mp4"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encodedPath)?alt=media"
    }
    
    public struct Engagement: Codable {
        public let viewCount: Int
        public let likeCount: Int
        public let dislikeCount: Int
        public let tags: [String: Int]  // tag name -> count of users who used this tag
        
        public static var empty: Engagement {
            Engagement(
                viewCount: 0,
                likeCount: 0,
                dislikeCount: 0,
                tags: [:]
            )
        }
        
        public init(
            viewCount: Int,
            likeCount: Int,
            dislikeCount: Int,
            tags: [String: Int]
        ) {
            self.viewCount = viewCount
            self.likeCount = likeCount
            self.dislikeCount = dislikeCount
            self.tags = tags
        }
    }
}

// Extension for Firestore conversion
extension Video {
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        
        guard let id = data["id"] as? String,
              let ownerId = data["ownerId"] as? String,
              let username = data["username"] as? String,
              let title = data["title"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else {
            return nil
        }
        
        self.id = id
        self.ownerId = ownerId
        self.username = username
        self.title = title
        self.description = data["description"] as? String
        self.createdAt = createdAt
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        self.random = data["random"] as? Int
        
        // Parse engagement data
        if let engagementData = data["engagement"] as? [String: Any] {
            self.engagement = Engagement(
                viewCount: engagementData["viewCount"] as? Int ?? 0,
                likeCount: engagementData["likeCount"] as? Int ?? 0,
                dislikeCount: engagementData["dislikeCount"] as? Int ?? 0,
                tags: engagementData["tags"] as? [String: Int] ?? [:]
            )
        } else {
            self.engagement = .empty
        }
    }
    
    var asFirestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "ownerId": ownerId,
            "username": username,
            "title": title,
            "description": description as Any,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "engagement": [
                "viewCount": engagement.viewCount,
                "likeCount": engagement.likeCount,
                "dislikeCount": engagement.dislikeCount,
                "tags": engagement.tags
            ]
        ]
        
        // Include random if present
        if let random = random {
            data["random"] = random
        }
        
        return data
    }
}

// MARK: - Comment Structure
// Comments will be stored in a subcollection under each video document
struct VideoComment: Codable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let text: String
    let createdAt: Date
    let likeCount: Int
    let dislikeCount: Int
    let replyTo: String?  // ID of parent comment if this is a reply
    
    // Tracks if the current user has reacted to this comment
    // These are populated when fetching comments
    var currentUserLiked: Bool?
    var currentUserDisliked: Bool?
    
    var asFirestoreData: [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "username": username,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "likeCount": likeCount,
            "dislikeCount": dislikeCount
        ]
        if let replyTo = replyTo {
            data["replyTo"] = replyTo
        }
        return data
    }
}

// MARK: - Comment Reaction Structure
struct CommentReaction: Codable {
    let userId: String
    let createdAt: Date
    let isLike: Bool  // true for like, false for dislike
    
    var asFirestoreData: [String: Any] {
        return [
            "userId": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "isLike": isLike
        ]
    }
}
