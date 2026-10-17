import Foundation

/// Actor-isolated networking client — the single source of truth.
/// Fully Swift 6 strict-concurrency safe.
public actor NetworkClient {
    
    private let configuration: NetworkConfiguration
    private let session: URLSession
    private let interceptors: [any Interceptor]
    
    public init(configuration: NetworkConfiguration) {
        self.configuration = configuration
        self.interceptors = configuration.interceptors
        self.session = URLSession(configuration: configuration.urlSessionConfiguration)
    }
    
    // MARK: - Public API
    
    public func request<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        // Allow one transparent retry after a successful token refresh
        try await performRequest(endpoint, isAuthRetry: false)
    }
    
    /// Fire-and-forget style request when you don't need the decoded body.
    public func requestVoid<E: Endpoint>(_ endpoint: E) async throws where E.Response == EmptyResponse {
        _ = try await request(endpoint)
    }
    
    /// Raw data request (useful for downloads or non-JSON payloads).
    public func requestData(for urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let context = RequestContext(request: urlRequest)
        
        for interceptor in interceptors {
            try await interceptor.prepare(context)
        }
        
        let (data, response) = try await session.data(for: context.request)
        context.data = data
        context.response = response
        
        for interceptor in interceptors.reversed() {
            try await interceptor.process(context)
        }
        
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (data, http)
    }
    
    // MARK: - Core Execution
    
    private func performRequest<E: Endpoint>(_ endpoint: E, isAuthRetry: Bool) async throws -> E.Response {
        let urlRequest = try buildURLRequest(for: endpoint)
        let context = RequestContext(request: urlRequest)
        
        // Propagate explicit idempotency key into metadata so interceptors can see it
        if let key = endpoint.idempotencyKey {
            context.metadata["idempotencyKey"] = key
        }
        
        // 1. Prepare interceptors (in order)
        for interceptor in interceptors {
            try await interceptor.prepare(context)
        }
        
        // 2. Execute with automatic cancellation support
        try Task.checkCancellation()
        
        do {
            let (data, response) = try await session.data(for: context.request)
            context.data = data
            context.response = response
        } catch let urlError as URLError {
            context.error = urlError
            if urlError.code == .cancelled {
                throw NetworkError.cancelled
            }
            throw mapTransportError(urlError)
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch {
            context.error = error
            throw NetworkError.unknown(error)
        }
        
        // 3. Process interceptors (reverse order – classic middleware pattern)
        for interceptor in interceptors.reversed() {
            try await interceptor.process(context)
        }
        
        // 4. Transparent retry after successful token refresh (only once)
        if !isAuthRetry,
           context.metadata["authRefreshed"] as? Bool == true {
            return try await performRequest(endpoint, isAuthRetry: true)
        }
        
        // 5. Validate HTTP status
        guard let httpResponse = context.httpResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.map(statusCode: httpResponse.statusCode, data: context.data)
        }
        
        // 6. Decode
        guard let data = context.data else {
            throw NetworkError.invalidResponse
        }
        
        do {
            return try configuration.decoder.decode(E.Response.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildURLRequest<E: Endpoint>(for endpoint: E) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = configuration.timeout
        
        // Default headers
        for (key, value) in configuration.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        // Endpoint-specific headers override
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Explicit Idempotency-Key from Endpoint (stable across retries)
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        
        if let cachePolicy = endpoint.cachePolicy {
            request.cachePolicy = cachePolicy
        }
        
        if let body = endpoint.body {
            do {
                request.httpBody = try configuration.encoder.encode(body)
            } catch {
                throw NetworkError.encoding(error)
            }
        }
        
        return request
    }
    
    private func mapTransportError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnectivity
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .transport(error)
        }
    }
}

/// Empty response type for endpoints that return no body (204, etc.).
public struct EmptyResponse: Decodable, Sendable {}
