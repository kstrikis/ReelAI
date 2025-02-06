import Combine
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseStorage
import Foundation

enum VideoPublishState {
    case creatingDocument
    case uploading(progress: Double)
    case updatingDocument
    case completed(Video)
    case error(Error)
}

final class VideoService {
    static let shared = VideoService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let uploadService = VideoUploadService.shared

    private init() {
        Log.p(Log.video, Log.start, "Initializing VideoService")
        Log.p(Log.video, Log.exit, "VideoService initialization complete")
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
                    Log.p(Log.firebase, Log.save, "Creating Firestore document for video")
                    let docRef = self.db.collection("videos").document()
                    let videoId = docRef.documentID
                    
                    // Create initial video object without media URL
                    let video = Video(
                        id: videoId,
                        ownerId: userId,
                        username: username,
                        title: title,
                        description: description,
                        mediaUrl: "", // Will be updated after upload
                        createdAt: Date(),
                        updatedAt: Date(),
                        engagement: .empty
                    )
                    
                    try await docRef.setData(from: video)
                    Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId)")
                    
                    // Return both the video object and the ID for use in upload
                    promise(.success((video, videoId)))
                } catch {
                    Log.p(Log.firebase, Log.save, Log.error, "Failed to create video document: \(error.localizedDescription)")
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

    func updateVideoMediaUrl(videoId: String, mediaUrl: String) -> AnyPublisher<Void, Error> {
        Log.p(Log.video, Log.update, "Updating video media URL for video: \(videoId)")
        
        return Future { promise in
            Task {
                do {
                    try await self.db.collection("videos").document(videoId).updateData([
                        "mediaUrl": mediaUrl,
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    Log.p(Log.video, Log.update, Log.success, "Successfully updated media URL")
                    promise(.success(()))
                } catch {
                    Log.p(Log.video, Log.update, Log.error, "Failed to update media URL: \(error.localizedDescription)")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }

    func publishVideo(
        url: URL,
        userId: String,
        username: String,
        title: String,
        description: String?
    ) -> AnyPublisher<VideoPublishState, Never> {
        Log.p(Log.video, Log.start, "Starting video publish process")
        
        return Future<VideoPublishState, Never> { promise in
            Task {
                do {
                    // 1. Create Firestore document first
                    promise(.success(.creatingDocument))
                    Log.p(Log.firebase, Log.save, "Creating Firestore document for video")
                    
                    let docRef = self.db.collection("videos").document()
                    let videoId = docRef.documentID
                    
                    let video = Video(
                        id: videoId,
                        ownerId: userId,
                        username: username,
                        title: title,
                        description: description,
                        mediaUrl: "", // Will be updated after upload
                        createdAt: Date(),
                        updatedAt: Date(),
                        engagement: .empty
                    )
                    
                    try await docRef.setData(from: video)
                    Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId)")
                    
                    // 2. Upload the video file
                    Log.p(Log.video, Log.uploadAction, "Starting video file upload")
                    let uploadPublisher = self.uploadService.uploadVideo(
                        at: url,
                        userId: userId,
                        videoId: videoId
                    )
                    
                    // Handle upload states
                    for await state in uploadPublisher.values {
                        switch state {
                        case let .progress(progress):
                            Log.p(Log.video, Log.uploadAction, "Upload progress for video \(videoId): \(Int(progress * 100))%")
                            promise(.success(.uploading(progress: progress)))
                            
                        case let .completed(ref):
                            // 3. Update document with storage URL
                            promise(.success(.updatingDocument))
                            Log.p(Log.firebase, Log.update, "Updating document with storage URL: \(ref.fullPath)")
                            
                            try await docRef.updateData([
                                "mediaUrl": ref.fullPath,
                                "updatedAt": FieldValue.serverTimestamp()
                            ])
                            
                            // 4. Get final video object
                            let finalDoc = try await docRef.getDocument(as: Video.self)
                            Log.p(Log.video, Log.event, Log.success, "Video \(videoId) published successfully")
                            promise(.success(.completed(finalDoc)))
                            
                        case let .failure(error):
                            Log.p(Log.video, Log.event, Log.error, "Video publish failed: \(error.localizedDescription)")
                            promise(.success(.error(error)))
                        }
                    }
                } catch {
                    Log.p(Log.video, Log.event, Log.error, "Video publish process error: \(error.localizedDescription)")
                    promise(.success(.error(error)))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in
                Log.p(Log.video, Log.event, "Video publish process started")
            },
            receiveCompletion: { _ in
                Log.p(Log.video, Log.exit, "Video publish process complete")
            },
            receiveCancel: {
                Log.p(Log.video, Log.event, Log.warning, "Video publish process cancelled")
            }
        )
        .eraseToAnyPublisher()
    }
}
