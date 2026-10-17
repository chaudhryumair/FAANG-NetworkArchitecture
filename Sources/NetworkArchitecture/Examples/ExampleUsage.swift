import Foundation

#if DEBUG

// MARK: - Example Models

public struct User: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let email: String
}

public struct CreateUserRequest: Codable, Sendable {
    public let name: String
    public let email: String
}

public struct Payment: Codable, Sendable {
    public let id: String
    public let amount: Decimal
    public let status: String
}

// MARK: - Example Endpoints

public struct GetUserEndpoint: Endpoint {
    public typealias Response = User
    
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public var path: String { "/v1/users/\(id)" }
    public var method: HTTPMethod { .get }
}

public struct ListUsersEndpoint: Endpoint {
    public typealias Response = [User]
    
    public var path: String { "/v1/users" }
    public var method: HTTPMethod { .get }
    public var queryItems: [URLQueryItem]? {
        [URLQueryItem(name: "limit", value: "50")]
    }
}

public struct CreateUserEndpoint: Endpoint {
    public typealias Response = User
    
    public let payload: CreateUserRequest
    
    public init(name: String, email: String) {
        self.payload = CreateUserRequest(name: name, email: email)
    }
    
    public var path: String { "/v1/users" }
    public var method: HTTPMethod { .post }
    public var body: (any Encodable & Sendable)? { payload }
}

/// Payment endpoint with a stable Idempotency-Key (mandatory for payment flows).
public struct CreatePaymentEndpoint: Endpoint {
    public typealias Response = Payment
    
    public let amount: Decimal
    public let idempotencyKey: String?
    
    public init(amount: Decimal, idempotencyKey: String = UUID().uuidString) {
        self.amount = amount
        self.idempotencyKey = idempotencyKey
    }
    
    public var path: String { "/v1/payments" }
    public var method: HTTPMethod { .post }
    public var body: (any Encodable & Sendable)? {
        ["amount": amount] as [String: Decimal]
    }
}

// MARK: - Factory (recommended DI pattern)

public enum NetworkFactory {
    
    /// Production-ready client with the full robustness stack.
    ///
    /// Recommended interceptor order:
    /// Metrics → CircuitBreaker → Auth → Idempotency → Logging → Retry → Cache
    @MainActor
    public static func makeProductionClient(
        baseURL: URL,
        tokenProvider: @escaping TokenProvider,
        refreshHandler: (@Sendable () async throws -> String)? = nil
    ) -> NetworkClient {
        
        let config = NetworkConfiguration(
            baseURL: baseURL,
            environment: .production,
            timeout: 30,
            interceptors: [
                // 1. Metrics – start timer / correlate request ID
                MetricsInterceptor { metric in
                    // Forward to your observability backend (Datadog, New Relic, etc.)
                    print("[Metrics] \(metric.method) \(metric.path) → \(metric.statusCode ?? -1) (\(Int(metric.durationMs))ms)")
                },
                
                // 2. Circuit Breaker – fail fast when a host is unhealthy
                CircuitBreakerInterceptor(
                    failureThreshold: 5,
                    recoveryTimeout: 30
                ),
                
                // 3. Auth – single-flight token refresh + optional retry policy
                AuthInterceptor(
                    tokenProvider: tokenProvider,
                    refreshHandler: refreshHandler,
                    refreshRetryPolicy: .once          // retry refresh once on failure
                ),
                
                // 4. Idempotency – protect POST/PUT/PATCH/DELETE
                IdempotencyInterceptor(),
                
                // 5. Logging
                LoggingInterceptor(level: .headers),
                
                // 6. Retry – transient failures with exponential backoff + jitter
                RetryInterceptor(maxAttempts: 3),
                
                // 7. Cache – hybrid memory + URLCache
                CacheInterceptor(policy: .returnCacheDataElseLoad)
            ]
        )
        
        return NetworkClient(configuration: config)
    }
    
    /// Lightweight client for development / previews (less aggressive).
    @MainActor
    public static func makeDevelopmentClient(
        baseURL: URL,
        tokenProvider: @escaping TokenProvider
    ) -> NetworkClient {
        
        let config = NetworkConfiguration(
            baseURL: baseURL,
            environment: .development,
            timeout: 60,
            interceptors: [
                LoggingInterceptor(level: .body),
                AuthInterceptor(tokenProvider: tokenProvider),
                IdempotencyInterceptor(),
                RetryInterceptor(maxAttempts: 2)
            ]
        )
        
        return NetworkClient(configuration: config)
    }
}

// MARK: - Usage Examples

/*

// 1. Create the client once (e.g. in a DI container or App dependency)
let client = NetworkFactory.makeProductionClient(
    baseURL: URL(string: "https://api.example.com")!,
    tokenProvider: { await TokenStore.shared.accessToken },
    refreshHandler: { try await TokenStore.shared.refresh() }
)

// 2. Simple GET
let user = try await client.request(GetUserEndpoint(id: "42"))

// 3. List with query params
let users = try await client.request(ListUsersEndpoint())

// 4. Create user (POST)
let newUser = try await client.request(
    CreateUserEndpoint(name: "Umair", email: "umair@example.com")
)

// 5. Payment with stable Idempotency-Key (critical for money movement)
let paymentKey = UUID().uuidString   // store this if you need to retry later
let payment = try await client.request(
    CreatePaymentEndpoint(amount: 49.99, idempotencyKey: paymentKey)
)

// Notes:
// - Token refresh is single-flight and automatically retries the original request once.
// - Circuit breaker protects against cascading failures.
// - Idempotency-Key is injected automatically for unsafe methods (or use the explicit one).

*/

#endif
