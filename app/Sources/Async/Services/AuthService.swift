import Foundation
import AppKit
import Network
import Supabase

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentSession: Session?
    @Published var isLoading = false
    @Published var error: String?

    private let supabase: SupabaseClient
    private var callbackServer: CallbackServer?

    init() {
        self.supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )

        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }

    var isAuthenticated: Bool {
        currentSession != nil
    }

    var currentUserId: UUID? {
        currentSession?.user.id
    }

    var githubHandle: String? {
        // GitHub handle is in user_metadata
        currentSession?.user.userMetadata["user_name"]?.stringValue
    }

    var displayName: String? {
        currentSession?.user.userMetadata["full_name"]?.stringValue
            ?? currentSession?.user.userMetadata["name"]?.stringValue
            ?? githubHandle
    }

    var avatarUrl: String? {
        currentSession?.user.userMetadata["avatar_url"]?.stringValue
    }

    var email: String? {
        currentSession?.user.email
    }

    // MARK: - Session Management

    func checkExistingSession() async {
        do {
            let session = try await supabase.auth.session
            self.currentSession = session
            print("✓ Restored existing session for: \(githubHandle ?? "unknown")")
        } catch {
            // No existing session - that's fine
            self.currentSession = nil
        }
    }

    // MARK: - GitHub OAuth

    func signInWithGitHub() async {
        isLoading = true
        error = nil

        // Start local callback server
        callbackServer = CallbackServer(port: 8080)

        do {
            try await callbackServer?.start()
            print("✓ Callback server started on port 8080")
        } catch {
            self.error = "Failed to start auth server: \(error.localizedDescription)"
            self.isLoading = false
            return
        }

        // Build OAuth URL with localhost redirect
        let redirectUri = "http://localhost:8080/callback"
        let encodedRedirect = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let oauthURL = URL(string: "\(Config.supabaseURL)/auth/v1/authorize?provider=github&redirect_to=\(encodedRedirect)")!

        print("Opening OAuth URL: \(oauthURL)")

        // Open in browser
        NSWorkspace.shared.open(oauthURL)

        // Wait for callback
        if let callbackURL = await callbackServer?.waitForCallback(timeout: 60) {
            print("Received callback: \(callbackURL)")

            // Stop server
            callbackServer?.stop()
            callbackServer = nil

            // Convert query params to fragment for Supabase SDK
            // Our JavaScript relay sends tokens as ?access_token=... but SDK expects #access_token=...
            let fragmentURL: URL
            if let query = callbackURL.query {
                // Convert query string to fragment
                var components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)!
                components.query = nil
                components.fragment = query
                fragmentURL = components.url!
                print("Converted to fragment URL: \(fragmentURL)")
            } else {
                fragmentURL = callbackURL
            }

            // Exchange callback for session
            do {
                let session = try await supabase.auth.session(from: fragmentURL)
                self.currentSession = session
                print("✓ Logged in as: \(githubHandle ?? "unknown")")
                await syncUserToDatabase()
            } catch {
                print("✘ Session error: \(error)")
                self.error = "Failed to complete login: \(error.localizedDescription)"
            }
        } else {
            callbackServer?.stop()
            callbackServer = nil
            self.error = "Login timed out. Please try again."
        }

        self.isLoading = false
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
            currentSession = nil
            print("✓ Signed out")
        } catch {
            self.error = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync to Users Table

    /// Ensure the authenticated user exists in our users table
    private func syncUserToDatabase() async {
        guard let userId = currentUserId,
              let handle = githubHandle else { return }

        do {
            // Check if user exists
            let existing: [UserRow] = try await supabase
                .from("users")
                .select()
                .eq("id", value: userId.uuidString)
                .execute()
                .value

            if existing.isEmpty {
                // Create user record
                let newUser = UserRow(
                    id: userId,
                    githubHandle: handle,
                    displayName: displayName ?? handle,
                    email: email,
                    avatarUrl: avatarUrl
                )

                try await supabase
                    .from("users")
                    .insert(newUser)
                    .execute()

                print("✓ Created user record for: \(handle)")
            } else {
                // Update existing user with latest GitHub info
                try await supabase
                    .from("users")
                    .update([
                        "display_name": displayName ?? handle,
                        "avatar_url": avatarUrl ?? "",
                        "email": email ?? ""
                    ])
                    .eq("id", value: userId.uuidString)
                    .execute()

                print("✓ Updated user record for: \(handle)")
            }
        } catch {
            print("⚠ Failed to sync user: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Types

private struct UserRow: Codable {
    let id: UUID
    let githubHandle: String?
    let displayName: String
    let email: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case githubHandle = "github_handle"
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
    }
}

// Extension to get string from AnyJSON
extension AnyJSON {
    var stringValue: String? {
        switch self {
        case .string(let str):
            return str
        default:
            return nil
        }
    }
}

// MARK: - Callback Server

/// Simple HTTP server to receive OAuth callbacks
class CallbackServer {
    private let port: UInt16
    private var listener: NWListener?
    private var receivedURL: URL?
    private var continuation: CheckedContinuation<URL?, Never>?

    init(port: UInt16) {
        self.port = port
    }

    func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Server ready on port \(self.port)")
            case .failed(let error):
                print("Server failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global())

        // Give it a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func waitForCallback(timeout: TimeInterval) async -> URL? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            // Set up timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.continuation != nil {
                    self.continuation?.resume(returning: nil)
                    self.continuation = nil
                }
            }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the HTTP request to get the URL
            if let urlLine = request.components(separatedBy: "\r\n").first,
               let path = urlLine.components(separatedBy: " ").dropFirst().first {

                // Check if this is the token relay request (has query params with tokens)
                if path.contains("access_token=") || path.contains("code=") {
                    // This is the second request with tokens - we have what we need
                    let fullURL = URL(string: "http://localhost:\(self.port)\(path)")

                    let html = """
                        <!DOCTYPE html>
                        <html>
                        <head><title>Login Successful</title></head>
                        <body style="font-family: system-ui; text-align: center; padding: 50px; background: #1a1a1a; color: white;">
                            <h1>✓ Login Successful!</h1>
                            <p>You can close this window and return to Async.</p>
                        </body>
                        </html>
                        """
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"

                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })

                    // Resume the continuation with the full URL including tokens
                    if let url = fullURL {
                        print("✓ Received OAuth tokens via relay")
                        self.receivedURL = url
                        self.continuation?.resume(returning: url)
                        self.continuation = nil
                    }
                } else {
                    // First request - no tokens yet (they're in the URL fragment)
                    // Return HTML with JavaScript to relay the fragment as query params
                    let html = """
                        <!DOCTYPE html>
                        <html>
                        <head><title>Completing Login...</title></head>
                        <body style="font-family: system-ui; text-align: center; padding: 50px; background: #1a1a1a; color: white;">
                            <h1>Completing login...</h1>
                            <p>Please wait...</p>
                            <script>
                                // URL fragments (after #) don't get sent to servers
                                // So we need to relay them via a second request
                                const fragment = window.location.hash.substring(1);
                                if (fragment) {
                                    // Relay the tokens as query params
                                    window.location.href = '/complete?' + fragment;
                                } else {
                                    document.body.innerHTML = '<h1>Login Error</h1><p>No authentication data received. Please try again.</p>';
                                }
                            </script>
                        </body>
                        </html>
                        """
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"

                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    // Don't resume yet - wait for the relay request with tokens
                }
            }
        }
    }
}
