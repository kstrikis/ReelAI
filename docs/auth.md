────────────────────────────
1. Overview & Objectives
────────────────────────────
• Use Combine to handle asynchronous tasks (such as network calls) in your authentication flow.  
• Create a reusable AuthenticationService that exposes its key operations (e.g., login, logout, token refresh) as publishers.  
• Leverage Combine’s operators (map, tryMap, decode, catch, retry, etc.) to transform responses and handle errors.  
• Ensure that subscriptions are managed (using AnyCancellable sets) to avoid memory leaks and correctly update the UI on the main thread.

────────────────────────────
2. Project Setup
────────────────────────────
• Confirm that our minimum target supports iOS 13 or later, as Combine requires this or newer.  
• Import Combine and any other required modules (e.g., Foundation) in your authentication-related files.

────────────────────────────
3. Designing the Authentication Service
────────────────────────────
• Define data models for credentials and responses. For example, create a Credentials struct and an AuthToken (or AuthResponse) model to capture the necessary data returned from the server.  
• Define a custom error type (e.g., AuthError) to encapsulate various failure scenarios (network issues, decoding failures, invalid responses, etc.).

Example:

--------------------------------------------------
import Foundation
import Combine

struct Credentials {
    let username: String
    let password: String
}

struct AuthToken: Decodable {
    let token: String
    let expiresIn: Int
}

enum AuthError: Error {
    case invalidResponse
    case network(Error)
    case decoding(Error)
    case unauthorized
}
--------------------------------------------------

────────────────────────────
4. Implementing the Login Publisher
────────────────────────────
• Create an AuthenticationService class with a login(with:) method.  
• Use URLSession’s dataTaskPublisher to perform the network request.  
• Chain operators to validate responses, decode the JSON into your AuthToken, and convert errors into your AuthError domain.  
• Erase the publisher’s type with eraseToAnyPublisher() so that callers don’t need to know about the underlying implementation details.

Example:

--------------------------------------------------
class AuthenticationService {
    private let baseURL = URL(string: "https://api.example.com")!
    
    func login(with credentials: Credentials) -> AnyPublisher<AuthToken, AuthError> {
        // Construct the URL and request
        let loginURL = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "username": credentials.username,
            "password": credentials.password
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .mapError { AuthError.network($0) } // Convert URLSession errors
            .tryMap { output -> Data in
                // Validate HTTP response
                guard let httpResponse = output.response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode else {
                    throw AuthError.invalidResponse
                }
                return output.data
            }
            .mapError { error in
                // Map errors thrown by tryMap to our AuthError type.
                error as? AuthError ?? AuthError.network(error)
            }
            // Decode the JSON into an AuthToken
            .decode(type: AuthToken.self, decoder: JSONDecoder())
            .mapError { AuthError.decoding($0) }
            .eraseToAnyPublisher()
    }
}
--------------------------------------------------

────────────────────────────
5. Integrating Combine in Your UI/ViewModel
────────────────────────────
• In your view model or view controller, call the login method and subscribe to the returned publisher.  
• Always switch to the main thread for UI updates by using .receive(on: DispatchQueue.main).  
• Use sink to handle both the value and the completion.  
• Store subscriptions in a Set<AnyCancellable> property to manage the subscription lifecycle.

Example:

--------------------------------------------------
import Combine
import SwiftUI

class AuthViewModel: ObservableObject {
    @Published var authToken: AuthToken?
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let authService = AuthenticationService()
    
    func login(username: String, password: String) {
        let credentials = Credentials(username: username, password: password)
        
        authService.login(with: credentials)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                switch completion {
                case .failure(let error):
                    self?.errorMessage = "Login failed: \(error)"
                case .finished:
                    break
                }
            } receiveValue: { [weak self] token in
                self?.authToken = token
                // Proceed with additional authentication logic if necessary
            }
            .store(in: &cancellables)
    }
}
--------------------------------------------------

────────────────────────────
6. Error Handling & Retry Strategies
────────────────────────────
• Consider using Combine’s .catch operator if you need to provide fallback behavior or default values on failure.  
• If the authentication call is prone to transient failures (e.g., temporary network issues), add a .retry(n) operator before .eraseToAnyPublisher() to automatically attempt a few retries.
• Always log or otherwise handle errors gracefully so that the user is informed of any issues.

────────────────────────────
7. Best Practices & Additional Considerations
────────────────────────────
• Keep your publishers pure—avoid side effects inside operators unless explicitly needed (e.g., for logging or metrics).  
• If you have multiple authentication-related calls (login, token refresh, logout), consider grouping them in the same AuthenticationService for consistency and reuse.  
• Use dependency injection to pass the AuthenticationService to your view model so that you can easily mock it during unit testing.  
• Write tests for your Combine pipelines using XCTest and expectations, ensuring that your authentication flows are reliable.  
• Document the expected behavior of the chain (e.g., how errors are mapped) so that future maintainers understand the flow.

────────────────────────────
8. Summary
────────────────────────────
• Use Combine to create a reactive, streamlined authentication flow that performs network requests, decodes responses, and seamlessly updates the UI.  
• Encapsulate the authentication logic in a dedicated AuthenticationService that returns AnyPublisher types for each auth operation.  
• Manage subscriptions carefully using AnyCancellable and ensure UI updates occur on the main thread.  
• Leverage Combine’s operators to handle retries, error mapping, and side-effect-free transformations.