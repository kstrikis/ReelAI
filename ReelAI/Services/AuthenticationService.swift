import Foundation
import FirebaseAuth
import FirebaseAuthCombineSwift
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Combine

/// Represents the current authentication state of the user
enum AuthState {
    case signedIn(User)
    case signedOut
    case error(Error)
}

/// Represents a user's profile data in Firestore
struct UserProfile: Codable {
    let username: String  // Unique handle/channel name (e.g., @demo123)
    let displayName: String
    let email: String?
    let profileImageUrl: String?
    let createdAt: Date
    
    init(username: String, displayName: String, email: String?, profileImageUrl: String? = nil, createdAt: Date = Date()) {
        self.username = username
        self.displayName = displayName
        self.email = email
        self.profileImageUrl = profileImageUrl
        self.createdAt = createdAt
    }
}

/// AuthenticationService handles all authentication-related operations
/// using Firebase Auth and provides a clean Combine-based interface.
final class AuthenticationService: ObservableObject {
    // MARK: - Properties
    
    /// Published auth state that UI can observe
    @Published private(set) var authState: AuthState = .signedOut
    
    /// Published user profile that UI can observe
    @Published private(set) var userProfile: UserProfile?
    
    /// Current user (if authenticated)
    var currentUser: User? {
        Auth.auth().currentUser
    }
    
    /// Store our subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Firestore reference
    private let db = Firestore.firestore()
    
    // MARK: - Initialization
    
    init() {
        AppLogger.methodEntry(AppLogger.auth)
        setupAuthStateHandler()
        AppLogger.methodExit(AppLogger.auth)
    }
    
    // MARK: - Auth State Handling
    
    private func setupAuthStateHandler() {
        AppLogger.methodEntry(AppLogger.auth)
        
        Auth.auth().authStateDidChangePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (auth: User?) in
                guard let self = self else { return }
                
                if let user = auth {
                    AppLogger.debug("👤 User signed in: \(user.uid)")
                    self.authState = .signedIn(user)
                    self.fetchUserProfile(userId: user.uid) // Fetch profile when signed in
                } else {
                    AppLogger.debug("👤 User signed out")
                    self.authState = .signedOut
                    self.userProfile = nil // Clear profile when signed out
                }
            }
            .store(in: &cancellables)
            
        AppLogger.methodExit(AppLogger.auth)
    }
    
    // MARK: - User Profile Methods
    
    /// Fetches the user's profile from Firestore
    /// - Parameter userId: The user's Firebase Auth UID
    private func fetchUserProfile(userId: String) {
        AppLogger.methodEntry(AppLogger.auth, params: ["userId": userId])
        
        db.collection("users").document(userId)
            .snapshotPublisher()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    AppLogger.error(AppLogger.auth, error, context: "Fetch user profile")
                }
            } receiveValue: { [weak self] snapshot in
                if let profile = try? snapshot.data(as: UserProfile.self) {
                    self?.userProfile = profile
                    AppLogger.debug("👤 User profile fetched: \(profile.displayName)")
                }
            }
            .store(in: &cancellables)
        
        AppLogger.methodExit(AppLogger.auth)
    }
    
    /// Generates a unique username from email or a base string
    /// - Parameter base: Base string to generate username from (e.g., email prefix or display name)
    /// - Returns: A publisher that emits a unique username or an error
    private func generateUniqueUsername(from base: String) -> AnyPublisher<String, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["base": base])
        
        // Remove special characters and spaces, convert to lowercase
        let sanitizedBase = base.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        
        // First try without a number
        return checkUsernameAvailability(sanitizedBase)
            .flatMap { isAvailable -> AnyPublisher<String, Error> in
                if isAvailable {
                    return Just(sanitizedBase)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
                
                // If not available, try with random numbers until we find an available one
                return self.findAvailableUsername(base: sanitizedBase)
            }
            .eraseToAnyPublisher()
    }
    
    /// Checks if a username is available
    /// - Parameter username: Username to check
    /// - Returns: A publisher that emits true if available, false if taken
    private func checkUsernameAvailability(_ username: String) -> AnyPublisher<Bool, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["username": username])
        
        return db.collection("usernames")
            .document(username)
            .getDocument()
            .map { !$0.exists }
            .eraseToAnyPublisher()
    }
    
    /// Finds an available username by appending random numbers
    /// - Parameter base: Base string to append numbers to
    /// - Returns: A publisher that emits an available username
    private func findAvailableUsername(base: String) -> AnyPublisher<String, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["base": base])
        
        // Try up to 100 random numbers (very unlikely to need this many)
        let attempts = (0..<100).map { _ in
            let randomNum = Int.random(in: 1...9999)
            let candidate = "\(base)\(randomNum)"
            return checkUsernameAvailability(candidate)
                .map { isAvailable -> String? in
                    isAvailable ? candidate : nil
                }
        }
        
        return Publishers.Sequence(sequence: attempts)
            .flatMap { $0 }
            .compactMap { $0 }
            .first()
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }
    
    /// Reserves a username in the usernames collection
    /// - Parameter username: Username to reserve
    /// - Returns: A publisher that completes when the username is reserved
    private func reserveUsername(_ username: String) -> AnyPublisher<Void, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["username": username])
        
        guard let userId = currentUser?.uid else {
            return Fail(error: NSError(domain: "com.kstrikis.ReelAI", code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]))
                .eraseToAnyPublisher()
        }
        
        return Future<Void, Error> { promise in
            self.db.collection("usernames").document(username).setData([
                "userId": userId,
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    AppLogger.error(AppLogger.auth, error, context: "Reserve username")
                    promise(.failure(error))
                } else {
                    AppLogger.debug("👤 Username reserved: \(username)")
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Creates or updates a user's profile in Firestore
    /// - Parameter profile: The profile data to save
    /// - Returns: A publisher that emits when the operation completes or errors
    func updateProfile(_ profile: UserProfile) -> AnyPublisher<Void, Error> {
        AppLogger.methodEntry(AppLogger.auth)
        
        guard let userId = currentUser?.uid else {
            let error = NSError(domain: "com.kstrikis.ReelAI", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        // First reserve the username, then update the profile
        return reserveUsername(profile.username)
            .flatMap { _ in
                Future<Void, Error> { promise in
                    do {
                        try self.db.collection("users").document(userId).setData(from: profile) { error in
                            if let error = error {
                                AppLogger.error(AppLogger.auth, error, context: "Update user profile")
                                promise(.failure(error))
                            } else {
                                AppLogger.debug("👤 User profile updated successfully")
                                promise(.success(()))
                            }
                        }
                    } catch {
                        AppLogger.error(AppLogger.auth, error, context: "Update user profile encoding")
                        promise(.failure(error))
                    }
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Authentication Methods
    
    /// Signs in with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: A publisher that emits the signed-in user or an error
    func signIn(email: String, password: String) -> AnyPublisher<User, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["email": email])
        
        return Future<User, Error> { promise in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error = error {
                    AppLogger.error(AppLogger.auth, error, context: "Sign in")
                    promise(.failure(error))
                    return
                }
                
                guard let user = result?.user else {
                    let error = NSError(domain: "com.kstrikis.ReelAI", code: -1, 
                                      userInfo: [NSLocalizedDescriptionKey: "User not found after sign in"])
                    AppLogger.error(AppLogger.auth, error, context: "Sign in - missing user")
                    promise(.failure(error))
                    return
                }
                
                AppLogger.methodExit(AppLogger.auth, result: "Success: \(user.uid)")
                promise(.success(user))
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    /// Signs in as a demo user
    /// - Returns: A publisher that emits the signed-in demo user or an error
    func signInAsDemo() -> AnyPublisher<User, Error> {
        AppLogger.methodEntry(AppLogger.auth)
        
        // Using a fixed demo account for simplicity
        // In production, you might want to use a pool of demo accounts or generate temporary ones
        return signIn(email: "demo@example.com", password: "demo123")
            .handleEvents(receiveOutput: { [weak self] user in
                AppLogger.debug("🎭 Demo user signed in successfully")
                
                // Create demo profile if it doesn't exist
                let profile = UserProfile(
                    username: "demo",
                    displayName: "Demo User",
                    email: user.email,
                    profileImageUrl: nil // Could add a default demo avatar URL here
                )
                
                self?.updateProfile(profile)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                AppLogger.error(AppLogger.auth, error, context: "Demo sign in - create profile")
                            }
                        },
                        receiveValue: { _ in
                            AppLogger.debug("🎭 Demo user profile created/updated")
                        }
                    )
                    .store(in: &self!.cancellables)
            })
            .eraseToAnyPublisher()
    }
    
    /// Creates a new user account with email and password and sets up their profile
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: A publisher that emits the created user or an error
    func signUp(email: String, password: String) -> AnyPublisher<User, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["email": email])
        
        return Future<User, Error> { promise in
            Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
                if let error = error {
                    AppLogger.error(AppLogger.auth, error, context: "Sign up")
                    promise(.failure(error))
                    return
                }
                
                guard let user = result?.user else {
                    let error = NSError(domain: "com.kstrikis.ReelAI", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "User not found after sign up"])
                    AppLogger.error(AppLogger.auth, error, context: "Sign up - missing user")
                    promise(.failure(error))
                    return
                }
                
                // Create initial profile
                let profile = UserProfile(
                    username: "user",
                    displayName: user.email?.components(separatedBy: "@").first ?? "User",
                    email: user.email
                )
                
                // Save profile to Firestore
                self?.updateProfile(profile)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                AppLogger.error(AppLogger.auth, error, context: "Sign up - create profile")
                                // Don't fail the signup if profile creation fails
                                // The profile can be created later
                                AppLogger.debug("👤 Profile creation failed, but continuing with sign up")
                            }
                            AppLogger.methodExit(AppLogger.auth, result: "Success: \(user.uid)")
                            promise(.success(user))
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self!.cancellables)
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
    
    /// Signs out the current user
    func signOut() {
        AppLogger.methodEntry(AppLogger.auth)
        
        do {
            try Auth.auth().signOut()
            AppLogger.methodExit(AppLogger.auth, result: "Success")
        } catch {
            AppLogger.error(AppLogger.auth, error, context: "Sign out")
            authState = .error(error)
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension AuthenticationService {
    /// Creates a preview instance of AuthenticationService
    static var preview: AuthenticationService {
        let service = AuthenticationService()
        // You can set up different auth states for previews here
        return service
    }
}
#endif 