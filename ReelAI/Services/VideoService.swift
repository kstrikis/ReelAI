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
        AppLogger.methodEntry(AppLogger.ui)
        print("📼 VideoService singleton initialized")
        AppLogger.methodExit(AppLogger.ui)
    }

    func createVideo(
        userId: String,
        username: String,
        title: String,
        description: String?
    ) -> AnyPublisher<(Video, String), Error> {
        AppLogger.methodEntry(AppLogger.ui)
        print("📼 Creating video metadata for user: \(username)")

        return Future { promise in
            Task {
                do {
                    print("📼 Creating Firestore document...")
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
                    print("📼 Video document created with ID: \(videoId)")
                    AppLogger.debug("Created video document with ID: \(videoId)")
                    
                    // Return both the video object and the ID for use in upload
                    promise(.success((video, videoId)))
                } catch {
                    print("❌ Failed to create video document: \(error.localizedDescription)")
                    AppLogger.error(AppLogger.ui, error)
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in
                print("📼 Video creation publisher subscribed")
            },
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("📼 Video creation completed successfully")
                case let .failure(error):
                    print("❌ Video creation failed: \(error.localizedDescription)")
                }
                AppLogger.methodExit(AppLogger.ui)
            },
            receiveCancel: {
                print("📼 Video creation cancelled")
                AppLogger.debug("Video creation cancelled")
            }
        )
        .eraseToAnyPublisher()
    }

    func updateVideoMediaUrl(videoId: String, mediaUrl: String) -> AnyPublisher<Void, Error> {
        return Future { promise in
            Task {
                do {
                    try await self.db.collection("videos").document(videoId).updateData([
                        "mediaUrl": mediaUrl,
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    promise(.success(()))
                } catch {
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
        print("📼 Starting video publish process")
        
        return Future<VideoPublishState, Never> { promise in
            Task {
                do {
                    // 1. Create Firestore document first
                    promise(.success(.creatingDocument))
                    print("📼 Creating Firestore document...")
                    
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
                    print("📼 Video document created with ID: \(videoId)")
                    
                    // 2. Upload the video file
                    print("📼 Starting video file upload...")
                    let uploadPublisher = self.uploadService.uploadVideo(
                        at: url,
                        userId: userId,
                        videoId: videoId
                    )
                    
                    // Handle upload states
                    for await state in uploadPublisher.values {
                        switch state {
                        case let .progress(progress):
                            promise(.success(.uploading(progress: progress)))
                            
                        case let .completed(ref):
                            // 3. Update document with storage URL
                            promise(.success(.updatingDocument))
                            print("📼 Updating document with storage URL...")
                            
                            try await docRef.updateData([
                                "mediaUrl": ref.fullPath,
                                "updatedAt": FieldValue.serverTimestamp()
                            ])
                            
                            // 4. Get final video object
                            let finalDoc = try await docRef.getDocument(as: Video.self)
                            promise(.success(.completed(finalDoc)))
                            
                        case let .failure(error):
                            promise(.success(.error(error)))
                        }
                    }
                } catch {
                    promise(.success(.error(error)))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in
                print("📼 Video publish process started")
            },
            receiveCompletion: { _ in
                print("📼 Video publish process completed")
            },
            receiveCancel: {
                print("📼 Video publish process cancelled")
            }
        )
        .eraseToAnyPublisher()
    }
}
