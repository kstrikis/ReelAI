import FirebaseFirestore
import Foundation

struct Video: Codable, Identifiable {
    let id: String
    let ownerId: String
    let username: String
    let title: String
    let description: String?
    let mediaUrl: String
    let createdAt: Date
    let updatedAt: Date
    let engagement: Engagement
    
    struct Engagement: Codable {
        let viewCount: Int
        let likeCount: Int
        let dislikeCount: Int
        let tags: [String: Int]  // tag name -> count of users who used this tag
        
        static var empty: Engagement {
            Engagement(
                viewCount: 0,
                likeCount: 0,
                dislikeCount: 0,
                tags: [:]
            )
        }
    }
}

// Extension for Firestore conversion
extension Video {
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        guard let ownerId = data["ownerId"] as? String,
              let username = data["username"] as? String,
              let title = data["title"] as? String,
              let mediaUrl = data["mediaUrl"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else {
            return nil
        }
        
        self.id = document.documentID
        self.ownerId = ownerId
        self.username = username
        self.title = title
        self.description = data["description"] as? String
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        
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
        return [
            "ownerId": ownerId,
            "username": username,
            "title": title,
            "description": description as Any,
            "mediaUrl": mediaUrl,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "engagement": [
                "viewCount": engagement.viewCount,
                "likeCount": engagement.likeCount,
                "dislikeCount": engagement.dislikeCount,
                "tags": engagement.tags
            ]
        ]
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
