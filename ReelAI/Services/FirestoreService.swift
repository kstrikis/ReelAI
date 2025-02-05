import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Combine
import Foundation

/// Manages all Firestore database operations
final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    
    private init() {
        AppLogger.dbEntry("Initializing FirestoreService")
    }
    
    // MARK: - User Profile Operations
    
    func createUserProfile(_ profile: UserProfile, userId: String) -> AnyPublisher<Void, Error> {
        AppLogger.dbWrite("Creating new user profile for \(userId)", collection: "users")
        
        return Future<Void, Error> { promise in
            do {
                let data = try profile.asDictionary()
                self.db.collection("users").document(userId).setData(data) { error in
                    if let error = error {
                        AppLogger.dbError("Failed to create user profile", error: error, collection: "users")
                        promise(.failure(error))
                    } else {
                        AppLogger.dbSuccess("Created user profile for \(userId)", collection: "users")
                        promise(.success(()))
                    }
                }
            } catch {
                AppLogger.dbError("Failed to encode user profile", error: error, collection: "users")
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }
    
    func updateUserProfile(_ profile: UserProfile, userId: String) -> AnyPublisher<Void, Error> {
        AppLogger.dbUpdate("Updating user profile for \(userId)", collection: "users")
        
        return Future<Void, Error> { promise in
            do {
                let data = try profile.asDictionary()
                self.db.collection("users").document(userId).setData(data, merge: true) { error in
                    if let error = error {
                        AppLogger.dbError("Failed to update user profile", error: error, collection: "users")
                        promise(.failure(error))
                    } else {
                        AppLogger.dbSuccess("Updated user profile for \(userId)", collection: "users")
                        promise(.success(()))
                    }
                }
            } catch {
                AppLogger.dbError("Failed to encode user profile update", error: error, collection: "users")
                promise(.failure(error))
            }
        }.eraseToAnyPublisher()
    }
    
    func getUserProfile(userId: String) -> AnyPublisher<UserProfile?, Error> {
        AppLogger.dbQuery("Fetching user profile for \(userId)", collection: "users")
        
        return Future<UserProfile?, Error> { promise in
            self.db.collection("users").document(userId).getDocument { snapshot, error in
                if let error = error {
                    AppLogger.dbError("Failed to fetch user profile", error: error, collection: "users")
                    promise(.failure(error))
                    return
                }
                
                guard let data = snapshot?.data() else {
                    AppLogger.dbEntry("No profile found for \(userId)", collection: "users")
                    promise(.success(nil))
                    return
                }
                
                do {
                    let profile = try UserProfile(dictionary: data)
                    AppLogger.dbSuccess("Fetched user profile for \(userId)", collection: "users")
                    promise(.success(profile))
                } catch {
                    AppLogger.dbError("Failed to decode user profile", error: error, collection: "users")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Video Operations
    
    func createVideo(title: String, description: String?, mediaUrl: String, userId: String, username: String) -> AnyPublisher<String, Error> {
        AppLogger.dbWrite("Creating new video document", collection: "videos")
        
        let data: [String: Any] = [
            "ownerId": userId,
            "username": username,
            "title": title,
            "description": description as Any,
            "mediaUrls": ["rawClip": mediaUrl],
            "createdAt": FieldValue.serverTimestamp(),
            "status": "uploaded"
        ]
        
        return Future<String, Error> { promise in
            self.db.collection("videos").addDocument(data: data) { error in
                if let error = error {
                    AppLogger.dbError("Failed to create video document", error: error, collection: "videos")
                    promise(.failure(error))
                } else {
                    AppLogger.dbSuccess("Created video document", collection: "videos")
                    promise(.success("Video document created successfully"))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    func getVideos(userId: String? = nil, limit: Int = 20) -> AnyPublisher<[VideoModel], Error> {
        AppLogger.dbQuery("Fetching videos" + (userId != nil ? " for user \(userId!)" : ""), collection: "videos")
        
        var query = db.collection("videos")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        
        if let userId = userId {
            query = query.whereField("ownerId", isEqualTo: userId)
        }
        
        return Future<[VideoModel], Error> { promise in
            query.getDocuments { snapshot, error in
                if let error = error {
                    AppLogger.dbError("Failed to fetch videos", error: error, collection: "videos")
                    promise(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    AppLogger.dbEntry("No videos found", collection: "videos")
                    promise(.success([]))
                    return
                }
                
                do {
                    let videos = try documents.map { try VideoModel(dictionary: $0.data(), id: $0.documentID) }
                    AppLogger.dbSuccess("Fetched \(videos.count) videos", collection: "videos")
                    promise(.success(videos))
                } catch {
                    AppLogger.dbError("Failed to decode videos", error: error, collection: "videos")
                    promise(.failure(error))
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