import Foundation
import FirebaseAuth
import FirebaseAuthCombineSwift
import Combine

/// Represents the current authentication state of the user
enum AuthState {
    case signedIn(User)
    case signedOut
    case error(Error)
}

/// AuthenticationService handles all authentication-related operations
/// using Firebase Auth and provides a clean Combine-based interface.
final class AuthenticationService: ObservableObject {
    // MARK: - Properties
    
    /// Published auth state that UI can observe
    @Published private(set) var authState: AuthState = .signedOut
    
    /// Current user (if authenticated)
    var currentUser: User? {
        Auth.auth().currentUser
    }
    
    /// Store our subscriptions
    private var cancellables = Set<AnyCancellable>()
    
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
                } else {
                    AppLogger.debug("👤 User signed out")
                    self.authState = .signedOut
                }
            }
            .store(in: &cancellables)
            
        AppLogger.methodExit(AppLogger.auth)
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
            .handleEvents(receiveOutput: { _ in
                AppLogger.debug("🎭 Demo user signed in successfully")
            })
            .eraseToAnyPublisher()
    }
    
    /// Creates a new user account with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: A publisher that emits the created user or an error
    func signUp(email: String, password: String) -> AnyPublisher<User, Error> {
        AppLogger.methodEntry(AppLogger.auth, params: ["email": email])
        
        return Future<User, Error> { promise in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
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
                
                AppLogger.methodExit(AppLogger.auth, result: "Success: \(user.uid)")
                promise(.success(user))
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