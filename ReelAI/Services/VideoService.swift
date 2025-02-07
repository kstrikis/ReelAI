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
    private var cancellables = Set<AnyCancellable>()

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
                    let docRef = self.db.collection("videos").document()
                    let videoId = docRef.documentID
                    
                    let video = Video(
                        id: videoId,
                        ownerId: userId,
                        username: username,
                        title: title,
                        description: description,
                        createdAt: Date(),
                        updatedAt: Date(),
                        engagement: .empty
                    )
                    
                    // Use proper async/await with error handling
                    do {
                        let encoder = Firestore.Encoder()
                        let data = try encoder.encode(video)
                        try await docRef.setData(data)
                        Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId)")
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
                
                let video = Video(
                    id: videoId,
                    ownerId: userId,
                    username: username,
                    title: title,
                    description: description,
                    createdAt: Date(),
                    updatedAt: Date(),
                    engagement: .empty
                )
                
                try await docRef.setData(from: video)
                Log.p(Log.firebase, Log.save, Log.success, "Video document created with ID: \(videoId)")
                
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
}
