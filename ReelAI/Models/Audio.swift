import Foundation
import FirebaseFirestore
import FirebaseFirestoreCombineSwift

struct Audio: Identifiable, Codable, Hashable {
    let id: String
    let storyId: String
    let sceneId: String? // nil for background music
    let userId: String
    let prompt: String
    let type: AudioType
    let voice: String? // Only for narration
    private let _displayName: String? // Backing storage for displayName
    let aimlapiUrl: String? // URL from AIMLAPI
    let mediaUrl: String? // Our Firebase Storage URL
    let generationId: String? // AIMLAPI generation ID for background music
    let createdAt: Date
    let status: AudioStatus
    
    init(
        id: String,
        storyId: String,
        sceneId: String?,
        userId: String,
        prompt: String,
        type: AudioType,
        voice: String?,
        _displayName: String?,
        aimlapiUrl: String?,
        mediaUrl: String?,
        generationId: String?,
        createdAt: Date,
        status: AudioStatus
    ) {
        self.id = id
        self.storyId = storyId
        self.sceneId = sceneId
        self.userId = userId
        self.prompt = prompt
        self.type = type
        self.voice = voice
        self._displayName = _displayName
        self.aimlapiUrl = aimlapiUrl
        self.mediaUrl = mediaUrl
        self.generationId = generationId
        self.createdAt = createdAt
        self.status = status
    }
    
    // Computed property that provides a fallback if _displayName is nil
    var displayName: String {
        if let name = _displayName {
            return name
        }
        
        // Fallback display name based on type and scene
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let timestamp = dateFormatter.string(from: createdAt)
        
        switch type {
        case .backgroundMusic:
            return "Background Music (\(timestamp))"
        case .narration:
            if let sceneId = sceneId {
                return "Narration - Scene \(String(sceneId.suffix(1))) (\(timestamp))"
            }
            return "Narration (\(timestamp))"
        case .soundEffect:
            if let sceneId = sceneId {
                return "Sound Effect - Scene \(String(sceneId.suffix(1))) (\(timestamp))"
            }
            return "Sound Effect (\(timestamp))"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, storyId, sceneId, userId, prompt, type, voice, aimlapiUrl, mediaUrl, generationId, createdAt, status
        case _displayName = "displayName"
    }
    
    enum AudioType: String, Codable {
        case backgroundMusic
        case narration
        case soundEffect
    }
    
    enum AudioStatus: String, Codable {
        case pending
        case generating
        case completed
        case failed
    }
    
    static func computeStoragePath(userId: String, storyId: String, audioId: String) -> String {
        return "users/\(userId)/stories/\(storyId)/audio/\(audioId).mp3"
    }
    
    static var mock: Audio {
        Audio(
            id: "audio_\(UUID().uuidString)",
            storyId: "story_123",
            sceneId: "scene_1",
            userId: "user_123",
            prompt: "Spooky wind sounds in a dark forest",
            type: .soundEffect,
            voice: nil,
            _displayName: nil,
            aimlapiUrl: nil,
            mediaUrl: nil,
            generationId: nil,
            createdAt: Date(),
            status: .pending
        )
    }
    
    // MARK: - Hashable Conformance
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Audio, rhs: Audio) -> Bool {
        lhs.id == rhs.id
    }
} 