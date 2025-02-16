import Combine
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseStorage
import Foundation
import FirebaseFunctions

enum VideoPublishState {
    case creatingDocument
    case uploading(progress: Double)
    case updatingDocument
    case completed(Video)
    case error(Error)
}

class VideoService: ObservableObject {
    static let shared = VideoService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let uploadService = VideoUploadService.shared
    private let authService: AuthenticationService
    private var cancellables = Set<AnyCancellable>()
    private let functions = Functions.functions()
    
    @Published private var generatingClips: Set<String> = []
    @Published private var clipStatuses: [String: String] = [:]
    private var clipListeners: [String: ListenerRegistration] = [:]
    
    deinit {
        // Remove all listeners when the service is deallocated
        clipListeners.values.forEach { $0.remove() }
    }
    
    private init() {
        self.authService = .preview
        Log.p(Log.video, Log.start, "Initializing VideoService")
        Log.p(Log.video, Log.exit, "VideoService initialization complete")
    }

    /// Gets the highest random index currently in use
    private func getHighestRandomIndex() async throws -> Int {
        let snapshot = try await db.collection("videos")
            .order(by: "random", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first,
              let randomValue = document.data()["random"] as? Int else {
                  Log.p(Log.firebase, Log.read, Log.warning, "No random value found in document")
            return -1 // Return -1 if no videos exist
        }
        
        Log.p(Log.firebase, Log.read, Log.success, "Found highest random value: \(randomValue)")
        return randomValue
    }

    func createVideo(
        userId: String,
        username: String,
        title: String,
        description: String?
    ) -> AnyPublisher<(Video, String), Error> {
        Log.p(Log.video, Log.start, "Creating video metadata for user: \(username)")

        return Future { promise in
            Task {
                do {
                    let docRef = self.db.collection("videos").document()
                    let videoId = docRef.documentID
                    
                    // Get the next random value
                    let nextRandomValue = try await self.getHighestRandomIndex() + 1
                    Log.p(Log.video, Log.save, "Got next random value: \(nextRandomValue)")
                    
                    let video = Video(
                        id: videoId,
                        ownerId: userId,
                        username: username,
                        title: title,
                        description: description,
                        createdAt: Date(),
                        updatedAt: Date(),
                        engagement: .empty,
                        random: nextRandomValue  // Add the random value here
                    )
                    
                    // Use proper async/await with error handling
                    do {
                        let encoder = Firestore.Encoder()
                        let data = try encoder.encode(video)
                        try await docRef.setData(data)
                        Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId) and random value: \(nextRandomValue)")
                        promise(.success((video, videoId)))
                    } catch {
                        throw error
                    }
                } catch {
                    Log.p(Log.firebase, Log.save, Log.error, "Failed to create video: \(error)")
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in
                Log.p(Log.video, Log.event, "Video creation publisher subscribed")
            },
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Log.p(Log.video, Log.event, Log.success, "Video creation completed successfully")
                case let .failure(error):
                    Log.p(Log.video, Log.event, Log.error, "Video creation failed: \(error.localizedDescription)")
                }
                Log.p(Log.video, Log.exit, "Video creation process complete")
            },
            receiveCancel: {
                Log.p(Log.video, Log.event, Log.warning, "Video creation cancelled")
            }
        )
        .eraseToAnyPublisher()
    }

    func publishVideo(
        url: URL,
        userId: String,
        username: String,
        title: String,
        description: String?
    ) -> AnyPublisher<VideoPublishState, Never> {
        Log.p(Log.video, Log.start, "Starting video publish process")
        
        let subject = PassthroughSubject<VideoPublishState, Never>()
        
        Task {
            do {
                subject.send(.creatingDocument)
                Log.p(Log.firebase, Log.save, "Creating Firestore document for video")
                
                let docRef = self.db.collection("videos").document()
                let videoId = docRef.documentID
                
                // Get the next random value
                let nextRandomValue = try await self.getHighestRandomIndex() + 1
                Log.p(Log.video, Log.save, "Got next random value: \(nextRandomValue)")
                
                let video = Video(
                    id: videoId,
                    ownerId: userId,
                    username: username,
                    title: title,
                    description: description,
                    createdAt: Date(),
                    updatedAt: Date(),
                    engagement: .empty,
                    random: nextRandomValue  // Add the random value here
                )
                
                try await docRef.setData(from: video)
                Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId) and random value: \(nextRandomValue)")
                
                Log.p(Log.video, Log.uploadAction, "Starting video file upload")
                let uploadPublisher = self.uploadService.uploadVideo(
                    at: url,
                    userId: userId,
                    videoId: videoId
                )
                
                // Subscribe to uploadPublisher using sink
                let uploadCancellable = uploadPublisher.sink { state in
                    switch state {
                    case let .progress(progress):
                        Log.p(Log.video, Log.uploadAction, "Upload progress for video \(videoId): \(Int(progress * 100))%")
                        subject.send(.uploading(progress: progress))
                    case let .completed(ref):
                        subject.send(.updatingDocument)
                        Log.p(Log.firebase, Log.update, "Updating document with storage URL: \(ref.fullPath)")
                        Task {
                            do {
                                try await docRef.updateData([
                                    "updatedAt": FieldValue.serverTimestamp()
                                ])
                                let finalDoc = try await docRef.getDocument(as: Video.self)
                                await MainActor.run {
                                    Log.p(Log.video, Log.event, Log.success, "Video \(videoId) published successfully")
                                    subject.send(.completed(finalDoc))
                                    subject.send(completion: .finished)
                                }
                            } catch {
                                await MainActor.run {
                                    Log.p(Log.video, Log.event, Log.error, "Error updating document: \(error.localizedDescription)")
                                    subject.send(.error(error))
                                    subject.send(completion: .finished)
                                }
                            }
                        }
                    case let .failure(error):
                        Log.p(Log.video, Log.event, Log.error, "Video publish failed: \(error.localizedDescription)")
                        subject.send(.error(error))
                        subject.send(completion: .finished)
                    }
                }
                uploadCancellable.store(in: &self.cancellables)
            } catch {
                Log.p(Log.video, Log.event, Log.error, "Video publish process error: \(error.localizedDescription)")
                subject.send(.error(error))
                subject.send(completion: .finished)
            }
        }
        
        return subject.eraseToAnyPublisher()
    }

    func isGenerating(for sceneId: String) -> Bool {
        generatingClips.contains(sceneId)
    }
    
    func generateClip(storyId: String, sceneId: String, prompt: String, duration: Double) async throws {
        guard let userId = authService.currentUser?.uid else {
            Log.p(Log.video, Log.event, Log.warning, "User not authenticated")
            throw NSError(
                domain: "VideoService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        // Mark as generating
        generatingClips.insert(sceneId)
        
        do {
            // Call the Cloud Function
            let result = try await functions.httpsCallable("generateVideo").call([
                "storyId": storyId,
                "sceneId": sceneId,
                "prompt": prompt,
                "duration": duration
            ])
            
            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  success,
                  let clipData = data["result"] as? [String: Any],
                  let clipId = clipData["id"] as? String else {
                Log.p(Log.video, Log.event, Log.error, "Invalid response format from generateVideo function")
                throw NSError(
                    domain: "VideoService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
                )
            }
            
            // Start listening for updates
            startListening(userId: userId, storyId: storyId, clipId: clipId, sceneId: sceneId)
            
        } catch {
            generatingClips.remove(sceneId)
            Log.error(Log.video, error, "Failed to generate clip")
            throw error
        }
    }
    
    private func startListening(userId: String, storyId: String, clipId: String, sceneId: String) {
        // Remove any existing listener for this scene
        clipListeners[sceneId]?.remove()
        
        // Create a new listener
        let listener = db.collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("videos")
            .document(clipId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    Log.error(Log.video, error, "Error listening for clip updates")
                    return
                }
                
                guard let data = snapshot?.data(),
                      let status = data["status"] as? String else {
                    return
                }
                
                clipStatuses[sceneId] = status
                
                if status == "completed" || status == "failed" {
                    generatingClips.remove(sceneId)
                    clipListeners[sceneId]?.remove()
                    clipListeners[sceneId] = nil
                }
            }
        
        clipListeners[sceneId] = listener
    }

    func recheckVideos(storyId: String) async throws {
        guard let userId = authService.currentUser?.uid else {
            Log.p(Log.video, Log.event, Log.warning, "User not authenticated")
            throw NSError(
                domain: "VideoService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        Log.p(Log.video, Log.start, "Rechecking videos for story: \(storyId)")
        
        // Get all pending or generating videos for this story
        let videoQuery = db.collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("videos")
            .whereField("status", in: ["pending", "generating"])
        
        let pendingVideos = try await videoQuery.getDocuments()
        
        if pendingVideos.isEmpty {
            Log.p(Log.video, Log.event, "No pending videos found for story: \(storyId)")
            return
        }
        
        // Call the Cloud Function to recheck each video
        let functions = Functions.functions()
        
        for doc in pendingVideos.documents {
            let videoId = doc.documentID
            Log.p(Log.video, Log.event, "Rechecking video: \(videoId)")
            
            do {
                let _ = try await functions.httpsCallable("recheckVideo").call([
                    "storyId": storyId,
                    "videoId": videoId
                ])
                Log.p(Log.video, Log.event, Log.success, "Recheck initiated for video: \(videoId)")
            } catch {
                Log.error(Log.video, error, "Failed to recheck video: \(videoId)")
                // Continue checking other videos even if one fails
                continue
            }
        }
        
        Log.p(Log.video, Log.exit, "Completed rechecking \(pendingVideos.count) videos")
    }
}

// MARK: - Preview Helper
extension VideoService {
    static var preview: VideoService {
        let service = VideoService()
        return service
    }
}
