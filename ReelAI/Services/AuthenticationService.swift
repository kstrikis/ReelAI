import Combine
import FirebaseAuth
import FirebaseAuthCombineSwift
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Foundation

/// Represents the current authentication state of the user
enum AuthState {
    case signedIn(User)
    case signedOut
    case error(Error)
}

/// Represents a user's profile data in Firestore
struct UserProfile: Codable {
    /// Unique handle/channel name (e.g., @demo123)
    let username: String
    let displayName: String
    let email: String?
    let profileImageUrl: String?
    let createdAt: Date

    init(
        username: String,
        displayName: String,
        email: String?,
        profileImageUrl: String? = nil,
        createdAt: Date = Date()
    ) {
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
    var cancellables = Set<AnyCancellable>()

    /// Firestore reference
    private let database = Firestore.firestore()

    // MARK: - Initialization

    init() {
        Log.p(Log.auth, Log.start, "Setting up authentication service")
        setupAuthStateHandler()
        Log.p(Log.auth, Log.exit, "Authentication service setup complete")
    }

    // MARK: - Auth State Handling

    private func setupAuthStateHandler() {
        Log.p(Log.auth_session, Log.start, "Setting up auth state handler")

        Auth.auth().authStateDidChangePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (auth: User?) in
                guard let self else { return }

                if let user = auth {
                    Log.p(Log.auth_session, Log.event, "User signed in: \(user.uid)")
                    print("👤 Firebase auth state changed - User signed in: \(user.uid)")
                    authState = .signedIn(user)

                    // Just fetch the profile, don't create a default one
                    database.collection("users").document(user.uid)
                        .snapshotPublisher()
                        .receive(on: DispatchQueue.main)
                        .sink { completion in
                            if case let .failure(error) = completion {
                                print("❌ Failed to fetch user profile: \(error.localizedDescription)")
                                Log.p(Log.auth, Log.event, Log.error, "Failed to fetch user profile: \(error.localizedDescription)")
                            }
                        } receiveValue: { [weak self] snapshot in
                            if let profile = try? snapshot.data(as: UserProfile.self) {
                                self?.userProfile = profile
                                print("✅ User profile loaded successfully:")
                                print("  - Username: \(profile.username)")
                                print("  - Display Name: \(profile.displayName)")
                                Log.p(Log.auth, Log.read, "User profile fetched: \(profile.displayName)")
                            } else {
                                print("⚠️ No valid profile found for user: \(user.uid)")
                            }
                        }
                        .store(in: &cancellables)
                } else {
                    print("👤 Firebase auth state changed - User signed out")
                    Log.p(Log.auth_session, Log.event, "User signed out")
                    authState = .signedOut
                    userProfile = nil // Clear profile when signed out
                }
            }
            .store(in: &cancellables)

        Log.p(Log.auth_session, Log.exit, "Auth state handler setup complete")
    }

    // MARK: - User Profile Methods

    /// Updates the local user profile
    /// - Parameter profile: The new profile to set
    func updateLocalProfile(_ profile: UserProfile) {
        Log.p(Log.auth, Log.start, "Updating local user profile")
        userProfile = profile
        Log.p(Log.auth, Log.exit, "Local user profile updated")
    }

    /// Fetches the user's profile from Firestore
    /// - Parameter userId: The user's Firebase Auth UID
    private func fetchUserProfile(userId: String) {
        Log.p(Log.auth, Log.read, "Fetching user profile: \(userId)")

        database.collection("users").document(userId)
            .snapshotPublisher()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    Log.p(Log.auth, Log.event, Log.error, "Failed to fetch user profile: \(error.localizedDescription)")
                }
            } receiveValue: { [weak self] snapshot in
                if let profile = try? snapshot.data(as: UserProfile.self) {
                    self?.userProfile = profile
                    Log.p(Log.auth, Log.read, "User profile fetched: \(profile.displayName)")
                }
            }
            .store(in: &cancellables)

        Log.p(Log.auth, Log.exit, "Profile fetch initiated")
    }

    /// Username validation rules
    enum UsernameValidationError: Error, LocalizedError {
        case tooShort
        case tooLong
        case invalidCharacters
        case startsWithNumber
        
        var errorDescription: String? {
            switch self {
            case .tooShort:
                return "Username must be at least 3 characters"
            case .tooLong:
                return "Username must be less than 30 characters"
            case .invalidCharacters:
                return "Username can only contain letters, numbers, and underscores"
            case .startsWithNumber:
                return "Username cannot start with a number"
            }
        }
    }
    
    /// Validates a username format
    /// - Parameter username: The username to validate
    /// - Returns: Result indicating if username is valid, with error if not
    private func validateUsername(_ username: String) -> Result<String, UsernameValidationError> {
        Log.p(Log.auth, Log.start, "Validating username")
        
        // Check length
        guard username.count >= 3 else {
            return .failure(.tooShort)
        }
        guard username.count < 30 else {
            return .failure(.tooLong)
        }
        
        // Check if starts with number
        if let first = username.first, first.isNumber {
            return .failure(.startsWithNumber)
        }
        
        // Check for valid characters (letters, numbers, underscore only)
        let validCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard username.unicodeScalars.allSatisfy({ validCharacterSet.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
        
        return .success(username)
    }

    /// Updates a user's profile in Firestore
    /// - Parameter profile: The profile data to save
    /// - Returns: A publisher that emits when the operation completes or errors
    func updateProfile(_ profile: UserProfile) -> AnyPublisher<Void, Error> {
        Log.p(Log.auth, Log.start, "Updating user profile")

        guard let userId = currentUser?.uid else {
            let error = NSError(
                domain: "com.edgineer.ReelAI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            )
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        // First validate username format
        let validationResult = validateUsername(profile.username)
        switch validationResult {
        case .failure(let error):
            return Fail(error: error).eraseToAnyPublisher()
        case .success:
            break
        }
        
        // Then check availability and update profile
        return checkUsernameAvailability(profile.username)
            .flatMap { isAvailable -> AnyPublisher<Void, Error> in
                if !isAvailable {
                    // If checking our own current username, that's okay
                    if let currentProfile = self.userProfile,
                       currentProfile.username == profile.username {
                        return self.updateProfileInFirestore(profile, userId: userId)
                    }
                    return Fail(error: NSError(
                        domain: "com.edgineer.ReelAI",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Username is already taken"]
                    )).eraseToAnyPublisher()
                }
                
                // Username is available, reserve it and update profile
                return self.reserveUsername(profile.username)
                    .flatMap { _ in
                        self.updateProfileInFirestore(profile, userId: userId)
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// Internal method to update profile in Firestore
    private func updateProfileInFirestore(_ profile: UserProfile, userId: String) -> AnyPublisher<Void, Error> {
        Future<Void, Error> { promise in
            do {
                try self.database.collection("users").document(userId).setData(from: profile) { error in
                    if let error {
                        Log.p(Log.auth, Log.event, Log.error, "Failed to update user profile: \(error.localizedDescription)")
                        promise(.failure(error))
                    } else {
                        Log.p(Log.auth, Log.event, "User profile updated successfully")
                        promise(.success(()))
                    }
                }
            } catch {
                Log.p(Log.auth, Log.event, Log.error, "Failed to encode user profile: \(error.localizedDescription)")
                promise(.failure(error))
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    /// Generates a unique username from email or a base string
    /// - Parameter base: Base string to generate username from (e.g., email prefix or display name)
    /// - Returns: A publisher that emits a unique username or an error
    private func generateUniqueUsername(from base: String) -> AnyPublisher<String, Error> {
        Log.p(Log.auth, Log.start, "Generating unique username from base: \(base)")

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
        Log.p(Log.auth, Log.read, "Checking username availability: \(username)")

        return database.collection("usernames")
            .document(username)
            .getDocument()
            .map { !$0.exists }
            .eraseToAnyPublisher()
    }

    /// Finds an available username by appending random numbers
    /// - Parameter base: Base string to append numbers to
    /// - Returns: A publisher that emits an available username
    private func findAvailableUsername(base: String) -> AnyPublisher<String, Error> {
        Log.p(Log.auth, Log.start, "Finding available username")

        // Try up to 100 random numbers (very unlikely to need this many)
        let attempts = (0 ..< 100).map { _ in
            let randomNum = Int.random(in: 1 ... 9999)
            let candidate = "\(base)\(randomNum)"
            return checkUsernameAvailability(candidate)
                .map { isAvailable -> String? in
                    isAvailable ? candidate : nil
                }
        }

        return Publishers.Sequence(sequence: attempts)
            .flatMap(\.self)
            .compactMap(\.self)
            .first()
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }

    /// Reserves a username in the usernames collection
    /// - Parameter username: Username to reserve
    /// - Returns: A publisher that completes when the username is reserved
    private func reserveUsername(_ username: String) -> AnyPublisher<Void, Error> {
        Log.p(Log.auth, Log.start, "Reserving username: \(username)")

        guard let userId = currentUser?.uid else {
            return Fail(error: NSError(
                domain: "com.edgineer.ReelAI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated user"]
            ))
            .eraseToAnyPublisher()
        }

        return Future<Void, Error> { promise in
            self.database.collection("usernames").document(username).setData([
                "userId": userId,
                "createdAt": FieldValue.serverTimestamp(),
            ]) { error in
                if let error {
                    Log.p(Log.auth, Log.event, Log.error, "Failed to reserve username: \(error.localizedDescription)")
                    promise(.failure(error))
                } else {
                    Log.p(Log.auth, Log.event, "Username reserved successfully: \(username)")
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Authentication Methods

    /// Signs in with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: A publisher that emits the signed-in user or an error
    func signIn(email: String, password: String) -> AnyPublisher<User, Error> {
        Log.p(Log.auth, Log.start, "Signing in user with email")

        return Future<User, Error> { promise in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    Log.p(Log.auth, Log.event, Log.error, "Sign in failed: \(error.localizedDescription)")
                    promise(.failure(error))
                    return
                }

                guard let user = result?.user else {
                    let error = NSError(
                        domain: "com.edgineer.ReelAI",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "User not found after sign in"]
                    )
                    Log.p(Log.auth, Log.event, Log.error, "Sign in failed: No user returned")
                    promise(.failure(error))
                    return
                }

                Log.p(Log.auth, Log.event, Log.success, "User signed in successfully: \(user.uid)")
                promise(.success(user))
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    /// Signs in as a demo user
    /// - Returns: A publisher that emits the signed-in demo user or an error
    func signInAsDemo() -> AnyPublisher<User, Error> {
        Log.p(Log.auth, Log.start, "Starting demo sign in process")
        print("🎭 Starting demo sign in process...")

        // Using a fixed demo account for simplicity
        return signIn(email: "demo@example.com", password: "demo123")
            .handleEvents(receiveOutput: { user in
                print("✅ Demo sign in completed successfully")
                print("  - User ID: \(user.uid)")
                print("  - Email: \(user.email ?? "none")")
            })
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Creates a new user account with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: A publisher that emits the created user or an error
    func signUp(email: String, password: String) -> AnyPublisher<User, Error> {
        Log.p(Log.auth, Log.start, "Starting user signup with email")

        return Future<User, Error> { promise in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    Log.p(Log.auth, Log.event, Log.error, "Sign up failed: \(error.localizedDescription)")
                    promise(.failure(error))
                    return
                }

                guard let user = result?.user else {
                    let error = NSError(
                        domain: "com.edgineer.ReelAI",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "User not found after sign up"]
                    )
                    Log.p(Log.auth, Log.event, Log.error, "Sign up failed: No user returned")
                    promise(.failure(error))
                    return
                }

                Log.p(Log.auth, Log.event, Log.success, "User created successfully: \(user.uid)")
                promise(.success(user))
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    /// Signs out the current user
    func signOut() {
        Log.p(Log.auth_session, Log.start, "Signing out user")
        do {
            try Auth.auth().signOut()
            Log.p(Log.auth_session, Log.event, Log.success, "User signed out successfully")
        } catch {
            Log.p(Log.auth_session, Log.event, Log.error, "Sign out failed: \(error.localizedDescription)")
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
