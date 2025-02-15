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
    let mediaUrl: String?
    let createdAt: Date
    let status: AudioStatus
    
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
            mediaUrl: nil,
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