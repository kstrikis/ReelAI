import Foundation
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import FirebaseStorage
import Combine

enum AudioServiceError: Error, LocalizedError {
    case encodingError
    case firestoreError(Error)
    case noUserLoggedIn
    case aiGenerationError(Error)
    case unexpectedError(Error)
    
    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode audio data"
        case .firestoreError(let error):
            return "Firestore error: \(error.localizedDescription)"
        case .noUserLoggedIn:
            return "No user is currently logged in"
        case .aiGenerationError(let error):
            return "AI Generation error: \(error.localizedDescription)"
        case .unexpectedError(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}

class AudioService: ObservableObject {
    @Published var currentAudio: [Audio] = []
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    init() {
        Log.p(Log.audio_music, Log.start, "Initializing AudioService")
    }
    
    // MARK: - Audio Generation
    
    func generateAudio(
        for story: Story,
        sceneId: String? = nil,
        type: Audio.AudioType,
        userId: String,
        completion: @escaping (Result<Audio, AudioServiceError>) -> Void
    ) {
        Log.p(Log.audio_music, Log.generate, "Generating audio for story: \(story.id), scene: \(sceneId ?? "background")")
        
        // Get the appropriate prompt based on type and scene
        let prompt: String
        let voice: String?
        
        switch type {
        case .backgroundMusic:
            prompt = story.backgroundMusicPrompt ?? "Gentle ambient background music"
            voice = nil
        case .narration:
            guard let sceneId = sceneId,
                  let scene = story.scenes.first(where: { scene in scene.id == sceneId }) else {
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scene not found"]))))
                return
            }
            prompt = scene.narration ?? ""
            voice = scene.voice
        case .soundEffect:
            guard let sceneId = sceneId,
                  let scene = story.scenes.first(where: { scene in scene.id == sceneId }) else {
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scene not found"]))))
                return
            }
            prompt = scene.audioPrompt ?? ""
            voice = nil
        }
        
        // For now, create a mock audio with pending status
        let audioId = "audio_\(UUID().uuidString)"
        let audio = Audio(
            id: audioId,
            storyId: story.id,
            sceneId: sceneId,
            userId: userId,
            prompt: prompt,
            type: type,
            voice: voice,
            mediaUrl: nil,
            createdAt: Date(),
            status: .pending
        )
        
        // Save to Firestore
        saveAudioToFirestore(audio) { [weak self] result in
            switch result {
            case .success:
                // Update local state
                DispatchQueue.main.async {
                    self?.currentAudio.append(audio)
                }
                completion(.success(audio))
                Log.p(Log.audio_music, Log.generate, Log.success, "Audio metadata created: \(audioId)")
                
            case .failure(let error):
                Log.error(Log.audio_music, error, "Failed to save audio metadata")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Firestore Operations
    
    private func saveAudioToFirestore(_ audio: Audio, completion: @escaping (Result<Void, AudioServiceError>) -> Void) {
        // Use the same path structure as defined in Audio.computeStoragePath
        let audioCollection = db.collection("users")
            .document(audio.userId)
            .collection("stories")
            .document(audio.storyId)
            .collection("audio")
        
        do {
            try audioCollection.document(audio.id).setData(from: audio) { error in
                if let error = error {
                    Log.error(Log.firebase, error, "Failed to save audio to Firestore")
                    completion(.failure(.firestoreError(error)))
                    return
                }
                Log.p(Log.firebase, Log.save, Log.success, "Audio saved to Firestore: \(audio.id)")
                completion(.success(()))
            }
        } catch {
            Log.error(Log.firebase, error, "Failed to encode audio for Firestore")
            completion(.failure(.encodingError))
        }
    }
    
    func loadAudio(for userId: String, storyId: String) {
        Log.p(Log.audio_music, Log.read, "Loading audio for story: \(storyId)")
        
        // Update the query path to match the new structure
        db.collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("audio")
            .order(by: "createdAt", descending: true)
            .snapshotPublisher()
            .map { snapshot -> [Audio] in
                snapshot.documents.compactMap { document in
                    try? document.data(as: Audio.self)
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    Log.error(Log.audio_music, error, "Failed to load audio")
                }
            } receiveValue: { [weak self] audio in
                self?.currentAudio = audio
                Log.p(Log.audio_music, Log.read, Log.success, "Loaded \(audio.count) audio items")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Mock Generation
    
    private func mockGenerateAudio(type: Audio.AudioType, completion: @escaping (URL?) -> Void) {
        // Simulate API delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // For now, return nil to simulate no audio file yet
            completion(nil)
        }
    }
} 