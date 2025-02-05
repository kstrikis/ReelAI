import Combine
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Foundation

final class VideoService {
    static let shared = VideoService()
    private let db = Firestore.firestore()

    private init() {
        AppLogger.methodEntry(AppLogger.ui)
        print("📼 VideoService singleton initialized")
        AppLogger.methodExit(AppLogger.ui)
    }

    func createVideo(userId: String, username: String, rawVideoURL: String) -> AnyPublisher<Video, Error> {
        AppLogger.methodEntry(AppLogger.ui)
        print("📼 Creating video metadata for user: \(username)")

        let video = Video(
            userId: userId,
            username: username,
            title: "Untitled Video",
            description: nil,
            rawVideoURL: rawVideoURL,
            processedVideoURL: nil,
            createdAt: nil,
            status: .uploading
        )

        print("📼 Video metadata prepared: \(rawVideoURL)")

        return Future { promise in
            Task {
                do {
                    print("📼 Adding video document to Firestore...")
                    let docRef = self.db.collection("videos").document()
                    try await docRef.setData(from: video)
                    print("📼 Video document created with ID: \(docRef.documentID)")
                    AppLogger.debug("Created video document with ID: \(docRef.documentID)")

                    // Return the created video with its ID
                    var createdVideo = video
                    createdVideo.id = docRef.documentID
                    promise(.success(createdVideo))
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

    func updateVideoStatus(_ videoId: String, status: VideoStatus) -> AnyPublisher<Void, Error> {
        AppLogger.methodEntry(AppLogger.ui)
        print("📼 Updating video status: \(videoId) -> \(status.rawValue)")

        return Future { promise in
            Task {
                do {
                    print("📼 Updating Firestore document...")
                    try await self.db.collection("videos").document(videoId).updateData([
                        "status": status.rawValue,
                    ])
                    print("📼 Video status updated successfully")
                    AppLogger.debug("Updated video status to: \(status.rawValue)")
                    promise(.success(()))
                } catch {
                    print("❌ Failed to update video status: \(error.localizedDescription)")
                    AppLogger.error(AppLogger.ui, error)
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(
            receiveSubscription: { _ in
                print("📼 Status update publisher subscribed")
            },
            receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("📼 Status update completed successfully")
                case let .failure(error):
                    print("❌ Status update failed: \(error.localizedDescription)")
                }
                AppLogger.methodExit(AppLogger.ui)
            },
            receiveCancel: {
                print("📼 Status update cancelled")
                AppLogger.debug("Status update cancelled")
            }
        )
        .eraseToAnyPublisher()
    }
}
