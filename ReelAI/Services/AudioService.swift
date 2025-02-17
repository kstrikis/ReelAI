import Foundation
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Combine
import FirebaseFunctions

enum AudioServiceError: Error, LocalizedError {
    case noUserLoggedIn
    case aiGenerationError(Error)
    case unexpectedError(Error)
    
    var errorDescription: String? {
        switch self {
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
        
        switch type {
        case .backgroundMusic:
            prompt = story.backgroundMusicPrompt ?? "Gentle ambient background music"
        case .narration:
            guard let sceneId = sceneId,
                  let scene = story.scenes.first(where: { scene in scene.id == sceneId }) else {
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scene not found"]))))
                return
            }
            prompt = scene.narration ?? ""
        case .soundEffect:
            guard let sceneId = sceneId,
                  let scene = story.scenes.first(where: { scene in scene.id == sceneId }) else {
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scene not found"]))))
                return
            }
            prompt = scene.audioPrompt ?? ""
        }
        
        // Call Firebase function to generate the audio
        callGenerateAudioFunction(
            storyId: story.id,
            sceneId: sceneId,
            type: type,
            prompt: prompt
        ) { result in
            switch result {
            case .success(let generationResult):
                // Create a local Audio object from the function result
                let audio = Audio(
                    id: generationResult.audioId,
                    storyId: story.id,
                    sceneId: sceneId,
                    userId: userId,
                    prompt: prompt,
                    type: type,
                    voice: type == .narration ? "ElevenLabs Brian" : nil,
                    _displayName: generationResult.displayName,
                    aimlapiUrl: generationResult.aimlapiUrl,
                    mediaUrl: generationResult.audioUrl,
                    generationId: generationResult.generationId,
                    createdAt: Date(),
                    status: Audio.AudioStatus(rawValue: generationResult.status) ?? .pending
                )
                completion(.success(audio))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func callGenerateAudioFunction(
        storyId: String,
        sceneId: String?,
        type: Audio.AudioType,
        prompt: String,
        completion: @escaping (Result<GenerationResult, AudioServiceError>) -> Void
    ) {
        Log.p(Log.audio_music, Log.generate, "Calling Firebase function to generate audio")
        
        let data: [String: Any] = [
            "storyId": storyId,
            "sceneId": sceneId as Any,
            "type": type.rawValue,
            "prompt": prompt
        ]
        
        Functions.functions().httpsCallable("generateAudio").call(data) { result, error in
            if let error = error {
                Log.error(Log.audio_music, error, "Firebase function error")
                completion(.failure(.aiGenerationError(error)))
                return
            }
            
            guard let resultData = result?.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  success,
                  let result = resultData["result"] as? [String: Any],
                  let id = result["id"] as? String else {
                Log.p(Log.audio_music, Log.generate, Log.error, "Invalid response format")
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))))
                return
            }
            
            // Create a local Audio object from the function result
            let generationResult = GenerationResult(
                audioId: id,
                audioUrl: result["mediaUrl"] as? String,
                displayName: result["displayName"] as? String,
                aimlapiUrl: result["aimlapiUrl"] as? String,
                generationId: result["generationId"] as? String,
                status: result["status"] as? String ?? "pending"
            )
            
            completion(.success(generationResult))
        }
    }
    
    private struct GenerationResult {
        let audioId: String
        let audioUrl: String?
        let displayName: String?
        let aimlapiUrl: String?
        let generationId: String?
        let status: String
    }
    
    struct RecheckResponse {
        let checkedCount: Int
        let updatedCount: Int
        let message: String
    }
    
    // MARK: - Audio Recheck
    
    func recheckAudio(
        for storyId: String,
        completion: @escaping (Result<RecheckResponse, AudioServiceError>) -> Void
    ) {
        Log.p(Log.audio_music, Log.verify, "Rechecking audio for story: \(storyId)")
        
        let data: [String: Any] = [
            "storyId": storyId
        ]
        
        Functions.functions().httpsCallable("recheckAudio").call(data) { result, error in
            if let error = error {
                Log.error(Log.audio_music, error, "Firebase function error")
                completion(.failure(.aiGenerationError(error)))
                return
            }
            
            guard let resultData = result?.data as? [String: Any],
                  let success = resultData["success"] as? Bool,
                  success,
                  let result = resultData["result"] as? [String: Any],
                  let checkedCount = result["checkedCount"] as? Int,
                  let updatedCount = result["updatedCount"] as? Int,
                  let message = result["message"] as? String else {
                Log.p(Log.audio_music, Log.verify, Log.error, "Invalid response format")
                completion(.failure(.unexpectedError(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))))
                return
            }
            
            let response = RecheckResponse(
                checkedCount: checkedCount,
                updatedCount: updatedCount,
                message: message
            )
            
            completion(.success(response))
        }
    }
    
    // MARK: - Firestore Listening
    
    func loadAudio(for userId: String, storyId: String) {
        Log.p(Log.audio_music, Log.read, "Loading audio for story: \(storyId), user: \(userId)")
        
        let path = "users/\(userId)/stories/\(storyId)/audio"
        Log.p(Log.audio_music, Log.read, "Querying Firestore path: \(path)")
        
        db.collection("users")
            .document(userId)
            .collection("stories")
            .document(storyId)
            .collection("audio")
            .order(by: "createdAt", descending: true)
            .snapshotPublisher()
            .map { snapshot -> [Audio] in
                Log.p(Log.audio_music, Log.read, "Received Firestore snapshot with \(snapshot.documents.count) documents")
                
                let audios = snapshot.documents.compactMap { document -> Audio? in
                    do {
                        let audio = try document.data(as: Audio.self)
                        Log.p(Log.audio_music, Log.read, Log.success, "Successfully decoded audio: \(audio.id), type: \(audio.type.rawValue)")
                        return audio
                    } catch {
                        Log.error(Log.audio_music, error, "Failed to decode audio document: \(document.documentID)")
                        return nil
                    }
                }
                
                Log.p(Log.audio_music, Log.read, "Successfully decoded \(audios.count) audio items")
                return audios
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    Log.error(Log.audio_music, error, "Failed to load audio")
                }
            } receiveValue: { [weak self] audios in
                guard let self = self else { return }
                // Remove any existing audio for this story
                self.currentAudio.removeAll { $0.storyId == storyId }
                // Add the new audio items
                self.currentAudio.append(contentsOf: audios)
                Log.p(Log.audio_music, Log.read, Log.success, "Updated currentAudio with \(audios.count) items for story \(storyId)")
            }
            .store(in: &cancellables)
    }
} 