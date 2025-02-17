import Foundation

struct Assembly: Codable, Identifiable, Hashable {
    let id: String
    let storyId: String
    let userId: String
    let displayName: String
    let status: String
    let mediaUrl: String?
    let createdAt: Date
    
    static func == (lhs: Assembly, rhs: Assembly) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 