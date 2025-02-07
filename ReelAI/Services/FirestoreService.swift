import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Combine
import Foundation
import FirebaseAuth

/// Manages all Firestore database operations
final class FirestoreService {
    static let shared = FirestoreService()
    private let db: Firestore
    private let authService: AuthenticationService
    
    private init() {
        Log.p(Log.firebase, Log.start, "Initializing FirestoreService")
        
        // Initialize Firestore
        db = Firestore.firestore()
        
        // Initialize auth service reference
        authService = AuthenticationService()
        
        // Log configuration details
        Log.p(Log.firebase, Log.event, "Firestore Configuration:")
        Log.p(Log.firebase, Log.event, "Project ID: \(db.app.options.projectID)")
        Log.p(Log.firebase, Log.event, "Storage Bucket: \(db.app.options.storageBucket)")
        
        // Enable network and verify connection
        db.enableNetwork { error in
            if let error = error {
                Log.p(Log.firebase, Log.event, Log.error, "Failed to enable network: \(error)")
            } else {
                Log.p(Log.firebase, Log.event, Log.success, "Network enabled")
            }
        }
        
        Log.p(Log.firebase, Log.start, Log.success, "Firestore service initialized")
    }
    
    // MARK: - User Profile Operations
    
    func createUserProfile(_ profile: UserProfile, userId: String) -> AnyPublisher<Void, Error> {
        Log.p(Log.firebase, Log.save, "Creating new user profile for \(userId)")
        
        // First reserve the username
        return Future<Void, Error> { promise in
            self.db.collection("usernames").document(profile.username).setData([
                "userId": userId,
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    Log.p(Log.firebase, Log.save, Log.error, "Failed to reserve username: \(error.localizedDescription)")
                    promise(.failure(error))
                    return
                }
                
                // Then create the user profile
                do {
                    let data = try profile.asDictionary()
                    self.db.collection("users").document(userId).setData(data) { error in
                        if let error = error {
                            // If profile creation fails, clean up the username reservation
                            self.db.collection("usernames").document(profile.username).delete { _ in
                                Log.p(Log.firebase, Log.save, Log.error, "Failed to create user profile: \(error.localizedDescription)")
                                promise(.failure(error))
                            }
                        } else {
                            Log.p(Log.firebase, Log.save, Log.success, "Created user profile for \(userId)")
                            promise(.success(()))
                        }
                    }
                } catch {
                    // If profile encoding fails, clean up the username reservation
                    self.db.collection("usernames").document(profile.username).delete { _ in
                        Log.p(Log.firebase, Log.save, Log.error, "Failed to encode user profile: \(error.localizedDescription)")
                        promise(.failure(error))
                    }
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func updateUserProfile(_ profile: UserProfile, userId: String) -> AnyPublisher<Void, Error> {
        Log.p(Log.firebase, Log.update, "Updating user profile for \(userId)")
        
        // Use the shared authService instance
        return authService.updateProfile(profile)
            .handleEvents(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Log.p(Log.firebase, Log.update, Log.success, "Updated user profile for \(userId)")
                case .failure(let error):
                    Log.p(Log.firebase, Log.update, Log.error, "Failed to update user profile: \(error.localizedDescription)")
                }
            })
            .eraseToAnyPublisher()
    }
    
    func getUserProfile(userId: String) -> AnyPublisher<UserProfile?, Error> {
        Log.p(Log.firebase, Log.read, "Fetching user profile for \(userId)")
        
        return Future<UserProfile?, Error> { promise in
            self.db.collection("users").document(userId).getDocument { snapshot, error in
                if let error = error {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to fetch user profile: \(error.localizedDescription)")
                    promise(.failure(error))
                    return
                }
                
                guard let data = snapshot?.data() else {
                    Log.p(Log.firebase, Log.read, Log.warning, "No profile found for \(userId)")
                    promise(.success(nil))
                    return
                }
                
                do {
                    let profile = try UserProfile(dictionary: data)
                    Log.p(Log.firebase, Log.read, Log.success, "Fetched user profile for \(userId)")
                    promise(.success(profile))
                } catch {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to decode user profile: \(error.localizedDescription)")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Video Operations
    
    func createVideo(title: String, description: String?, userId: String, username: String) -> AnyPublisher<String, Error> {
        Log.p(Log.firebase, Log.save, "Creating new video document")
        Log.p(Log.firebase, Log.event, "Video metadata:")
        Log.p(Log.firebase, Log.event, "Title: \(title)")
        Log.p(Log.firebase, Log.event, "User ID: \(userId)")
        
        let video = Video(
            id: UUID().uuidString,  // Will be replaced by Firestore document ID
            ownerId: userId,
            username: username,
            title: title,
            description: description,
            createdAt: Date(),      // Will be replaced by server timestamp
            updatedAt: Date(),      // Will be replaced by server timestamp
            engagement: .empty
        )
        
        return Future<String, Error> { promise in
            // Verify Firebase Auth state first
            guard let currentUser = Auth.auth().currentUser,
                  currentUser.uid == userId else {
                let error = NSError(domain: "com.edgineer.ReelAI",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Authentication mismatch or missing"])
                Log.p(Log.firebase, Log.save, Log.error, "Failed to create video - auth mismatch")
                promise(.failure(error))
                return
            }
            
            Log.p(Log.firebase, Log.save, "Creating document in 'videos' collection...")
            self.db.collection("videos").addDocument(data: video.asFirestoreData) { error in
                if let error = error {
                    Log.p(Log.firebase, Log.save, Log.error, "Failed to create video document: \(error.localizedDescription)")
                    promise(.failure(error))
                } else {
                    Log.p(Log.firebase, Log.save, Log.success, "Created video document successfully")
                    promise(.success("Video document created successfully"))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func getVideos(userId: String? = nil, limit: Int = 20) -> AnyPublisher<[Video], Error> {
        Log.p(Log.firebase, Log.read, "Fetching videos" + (userId != nil ? " for user \(userId!)" : ""))
        
        var query = db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let userId = userId {
            query = query.whereField("ownerId", isEqualTo: userId)
        }
        
        return Future<[Video], Error> { promise in
            query.getDocuments { snapshot, error in
                if let error = error {
                    Log.p(Log.firebase, Log.read, Log.error, "Failed to fetch videos: \(error.localizedDescription)")
                    promise(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    Log.p(Log.firebase, Log.read, Log.warning, "No videos found")
                    promise(.success([]))
                    return
                }
                
                let videos = documents.compactMap { Video(document: $0) }
                Log.p(Log.firebase, Log.read, Log.success, "Fetched \(videos.count) videos")
                promise(.success(videos))
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Video Engagement Operations
    
    func incrementVideoView(videoId: String) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let ref = self.db.collection("videos").document(videoId)
            ref.updateData([
                "engagement.viewCount": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func updateVideoLike(videoId: String, isLike: Bool, increment: Bool) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let field = isLike ? "engagement.likeCount" : "engagement.dislikeCount"
            let value = increment ? 1 : -1
            
            let ref = self.db.collection("videos").document(videoId)
            ref.updateData([
                field: FieldValue.increment(Int64(value)),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func addVideoTag(videoId: String, tag: String) -> AnyPublisher<Void, Error> {
        return Future<Void, Error> { promise in
            let ref = self.db.collection("videos").document(videoId)
            ref.updateData([
                "engagement.tags.\(tag)": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Comment Operations
    
    func addComment(to videoId: String, text: String, replyTo: String? = nil) -> AnyPublisher<String, Error> {
        guard let currentUser = Auth.auth().currentUser else {
            return Fail(error: NSError(domain: "com.edgineer.ReelAI",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]))
                .eraseToAnyPublisher()
        }
        
        let comment = VideoComment(
            id: UUID().uuidString,
            userId: currentUser.uid,
            username: currentUser.displayName ?? "unknown",
            text: text,
            createdAt: Date(),
            likeCount: 0,
            dislikeCount: 0,
            replyTo: replyTo,
            currentUserLiked: nil,
            currentUserDisliked: nil
        )
        
        return Future<String, Error> { promise in
            self.db.collection("videos").document(videoId)
                .collection("comments")
                .addDocument(data: comment.asFirestoreData) { error in
                    if let error = error {
                        promise(.failure(error))
                    } else {
                        promise(.success("Comment added successfully"))
                    }
                }
        }.eraseToAnyPublisher()
    }
    
    func getComments(for videoId: String, limit: Int = 50) -> AnyPublisher<[VideoComment], Error> {
        let currentUserId = Auth.auth().currentUser?.uid
        
        return Future<[VideoComment], Error> { promise in
            self.db.collection("videos").document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments { [weak self] snapshot, error in
                    if let error = error {
                        promise(.failure(error))
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        promise(.success([]))
                        return
                    }
                    
                    // First create comments without reaction status
                    var comments = documents.compactMap { document -> VideoComment? in
                        let data = document.data()
                        return VideoComment(
                            id: document.documentID,
                            userId: data["userId"] as? String ?? "",
                            username: data["username"] as? String ?? "",
                            text: data["text"] as? String ?? "",
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            likeCount: data["likeCount"] as? Int ?? 0,
                            dislikeCount: data["dislikeCount"] as? Int ?? 0,
                            replyTo: data["replyTo"] as? String,
                            currentUserLiked: nil,
                            currentUserDisliked: nil
                        )
                    }
                    
                    // If no user is logged in, return comments as is
                    guard let currentUserId = currentUserId else {
                        promise(.success(comments))
                        return
                    }
                    
                    // Create a dispatch group to wait for all reaction checks
                    let group = DispatchGroup()
                    
                    // Check reactions for each comment
                    for i in 0..<comments.count {
                        group.enter()
                        self?.checkUserReaction(
                            videoId: videoId,
                            commentId: comments[i].id,
                            userId: currentUserId
                        ) { liked, disliked in
                            comments[i].currentUserLiked = liked
                            comments[i].currentUserDisliked = disliked
                            group.leave()
                        }
                    }
                    
                    // When all reactions are checked, return the comments
                    group.notify(queue: .main) {
                        promise(.success(comments))
                    }
                }
        }.eraseToAnyPublisher()
    }
    
    private func checkUserReaction(videoId: String, commentId: String, userId: String, completion: @escaping (Bool, Bool) -> Void) {
        let reactionsRef = db.collection("videos").document(videoId)
            .collection("comments").document(commentId)
            .collection("reactions")
        
        reactionsRef.whereField("userId", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("Error checking reactions: \(error)")
                completion(false, false)
                return
            }
            
            var liked = false
            var disliked = false
            
            if let documents = snapshot?.documents {
                for doc in documents {
                    if let isLike = doc.data()["isLike"] as? Bool {
                        if isLike {
                            liked = true
                        } else {
                            disliked = true
                        }
                    }
                }
            }
            
            completion(liked, disliked)
        }
    }
    
    func updateCommentReaction(videoId: String, commentId: String, isLike: Bool, add: Bool) -> AnyPublisher<Void, Error> {
        guard let currentUser = Auth.auth().currentUser else {
            return Fail(error: NSError(domain: "com.edgineer.ReelAI",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]))
                .eraseToAnyPublisher()
        }
        
        return Future<Void, Error> { promise in
            let batch = self.db.batch()
            
            // Reference to the comment document
            let commentRef = self.db.collection("videos").document(videoId)
                .collection("comments").document(commentId)
            
            // Reference to the reactions subcollection
            let reactionsRef = commentRef.collection("reactions")
            
            // First, get the user's current reaction
            reactionsRef.whereField("userId", isEqualTo: currentUser.uid).getDocuments { snapshot, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }
                
                // Remove any existing reactions
                snapshot?.documents.forEach { doc in
                    batch.deleteDocument(doc.reference)
                    
                    // Decrement the corresponding counter
                    if let existingReaction = doc.data()["isLike"] as? Bool {
                        let field = existingReaction ? "likeCount" : "dislikeCount"
                        batch.updateData([field: FieldValue.increment(Int64(-1))], forDocument: commentRef)
                    }
                }
                
                // If adding a new reaction
                if add {
                    // Add the new reaction document
                    let reaction = CommentReaction(
                        userId: currentUser.uid,
                        createdAt: Date(),
                        isLike: isLike
                    )
                    
                    let newReactionRef = reactionsRef.document()
                    batch.setData(reaction.asFirestoreData, forDocument: newReactionRef)
                    
                    // Increment the corresponding counter
                    let field = isLike ? "likeCount" : "dislikeCount"
                    batch.updateData([field: FieldValue.increment(Int64(1))], forDocument: commentRef)
                }
                
                // Commit the batch
                batch.commit { error in
                    if let error = error {
                        promise(.failure(error))
                    } else {
                        promise(.success(()))
                    }
                }
            }
        }.eraseToAnyPublisher()
    }
}

// MARK: - Model Extensions

extension UserProfile {
    func asDictionary() throws -> [String: Any] {
        return [
            "displayName": displayName,
            "username": username,
            "email": email as Any,
            "profileImageUrl": profileImageUrl as Any,
            "createdAt": createdAt
        ]
    }
    
    init(dictionary: [String: Any]) throws {
        self.displayName = dictionary["displayName"] as? String ?? ""
        self.username = dictionary["username"] as? String ?? ""
        self.email = dictionary["email"] as? String
        self.profileImageUrl = dictionary["profileImageUrl"] as? String
        self.createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

struct VideoModel: Identifiable, Codable {
    let id: String
    let ownerId: String
    let username: String
    let title: String
    let description: String?
    let mediaUrls: [String: String]
    let createdAt: Date
    let status: String
    
    init(dictionary: [String: Any], id: String) throws {
        self.id = id
        self.ownerId = dictionary["ownerId"] as? String ?? ""
        self.username = dictionary["username"] as? String ?? ""
        self.title = dictionary["title"] as? String ?? ""
        self.description = dictionary["description"] as? String
        self.mediaUrls = dictionary["mediaUrls"] as? [String: String] ?? [:]
        self.createdAt = (dictionary["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.status = dictionary["status"] as? String ?? "unknown"
    }
} 