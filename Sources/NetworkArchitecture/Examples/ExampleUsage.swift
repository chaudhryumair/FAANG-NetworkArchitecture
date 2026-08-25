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

// MARK: - Factory (recommended DI pattern)

public enum NetworkFactory {
    
    @MainActor
    public static func makeProductionClient(
        baseURL: URL,
        tokenProvider: @escaping TokenProvider
    ) -> NetworkClient {
        
        let config = NetworkConfiguration(
            baseURL: baseURL,
            environment: .production,
            interceptors: [
                MetricsInterceptor { metric in
                    // Forward to your observability backend
                    print("[Metrics] \(metric.method) \(metric.path) → \(metric.statusCode ?? -1) (\(Int(metric.durationMs))ms)")
                },
                LoggingInterceptor(level: .headers),
                AuthInterceptor(tokenProvider: tokenProvider),
                RetryInterceptor(maxAttempts: 3),
                CacheInterceptor(policy: .returnCacheDataElseLoad)
            ]
        )
        
        return NetworkClient(configuration: config)
    }
}

#endif
