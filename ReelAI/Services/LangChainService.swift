import Foundation
import Combine
import FirebaseFunctions
import FirebaseAuth

/// Service to handle story generation through Firebase Cloud Functions
final class LangChainService {
    static let shared = LangChainService()
    private let functions: Functions
    
    private init() {
        #if DEBUG
        // Use local emulator in debug builds if available
        self.functions = Functions.functions()
        if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
            functions.useEmulator(withHost: "localhost", port: 5001)
        }
        #else
        self.functions = Functions.functions()
        #endif
        
        Log.p(Log.ai_story, Log.start, "LangChain service initialized with Firebase Functions")
    }
    
    /// Generates a story using Firebase Cloud Function
    /// - Parameter prompt: User's story prompt
    /// - Returns: Generated Story
    func generateStory(from prompt: String) async throws -> Story {
        Log.p(Log.ai_story, Log.generate, "Requesting story generation via Cloud Function")
        
        // Ensure user is authenticated
        guard let _ = Auth.auth().currentUser else {
            Log.error(Log.ai_story, LangChainError.unauthorized)
            throw LangChainError.unauthorized
        }
        
        do {
            // Call the Firebase Cloud Function
            let result = try await functions
                .httpsCallable("generateStory")
                .call(["prompt": prompt])
            
            // Log the raw response data
            if let data = result.data as? [String: Any] {
                Log.p(Log.ai_story, Log.generate, "Raw response data: \(data)")
                if let resultData = data["result"] as? [String: Any] {
                    Log.p(Log.ai_story, Log.generate, "Story data: \(resultData)")
                }
            }
            
            // Parse the response
            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  let resultData = data["result"] as? [String: Any],
                  success else {
                throw LangChainError.parsingError("Invalid response format")
            }
            
            // Convert to JSON data for decoding
            let jsonData: Data
            do {
                jsonData = try JSONSerialization.data(withJSONObject: resultData, options: [.prettyPrinted, .sortedKeys])
                Log.p(Log.ai_story, Log.generate, "Serialized JSON: \(String(data: jsonData, encoding: .utf8) ?? "nil")")
            } catch {
                Log.error(Log.ai_story, error, "Failed to serialize response data")
                throw LangChainError.parsingError("Failed to serialize response: \(error.localizedDescription)")
            }

            let decoder = JSONDecoder()
            
            // Configure date decoding strategy
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)
                
                // Try parsing with fractional seconds
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                
                // If that fails, try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateStr) {
                    return date
                }
                
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateStr)")
            }
            
            do {
                let story = try decoder.decode(Story.self, from: jsonData)
                Log.p(Log.ai_story, Log.generate, Log.success, "Story generated successfully")
                return story
            } catch {
                Log.error(Log.ai_story, error, "Failed to decode story: \(String(describing: error))")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, _):
                        throw LangChainError.parsingError("Missing key: \(key.stringValue)")
                    case .typeMismatch(let type, let context):
                        throw LangChainError.parsingError("Type mismatch: expected \(type) for key \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        throw LangChainError.parsingError("Value not found: expected \(type) for key \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    default:
                        throw LangChainError.parsingError("Decoding error: \(error.localizedDescription)")
                    }
                }
                throw error
            }
            
        } catch let error as NSError {
            switch error.domain {
            case FunctionsErrorDomain:
                switch FunctionsErrorCode(rawValue: error.code) {
                case .notFound:
                    Log.error(Log.ai_story, LangChainError.functionNotFound)
                    throw LangChainError.functionNotFound
                case .unauthenticated:
                    Log.error(Log.ai_story, LangChainError.unauthorized)
                    throw LangChainError.unauthorized
                case .resourceExhausted:
                    Log.error(Log.ai_story, LangChainError.rateLimited)
                    throw LangChainError.rateLimited
                default:
                    let message = error.localizedDescription
                    Log.error(Log.ai_story, LangChainError.apiError(message))
                    throw LangChainError.apiError(message)
                }
            default:
                Log.error(Log.ai_story, error)
                throw error
            }
        }
    }
}

// MARK: - Error Types

enum LangChainError: Error, LocalizedError {
    case functionNotFound
    case unauthorized
    case rateLimited
    case apiError(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .functionNotFound:
            return "Story generation function not found"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .apiError(let message):
            return "API Error: \(message)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
} 