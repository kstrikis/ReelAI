import Foundation

@MainActor
class UserSettings: ObservableObject {
    static let shared = UserSettings()
    
    enum VideoFeedOrder: String, CaseIterable {
        case chronological = "Chronological"
        case random = "Random"
        
        var description: String {
            switch self {
            case .chronological:
                return "Show newest videos first"
            case .random:
                return "Show videos in random order"
            }
        }
    }
    
    @Published var videoFeedOrder: VideoFeedOrder {
        didSet {
            UserDefaults.standard.set(videoFeedOrder.rawValue, forKey: "videoFeedOrder")
        }
    }
    
    private init() {
        // Load saved settings or use defaults
        if let savedOrder = UserDefaults.standard.string(forKey: "videoFeedOrder"),
           let order = VideoFeedOrder(rawValue: savedOrder) {
            self.videoFeedOrder = order
        } else {
            self.videoFeedOrder = .chronological
        }
    }
} 