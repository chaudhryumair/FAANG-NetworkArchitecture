import XCTest
@testable import NetworkArchitecture

// MARK: - Sample Models & Endpoints (used across tests)

private struct User: Codable, Sendable, Equatable {
    let id: String
    let name: String
}

private struct GetUserEndpoint: Endpoint {
    typealias Response = User
    let id: String
    
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .get }
}

private struct CreatePaymentEndpoint: Endpoint {
    typealias Response = User   // simplified for tests
    let amount: Decimal
    let idempotencyKey: String?
    
    var path: String { "/v1/payments" }
    var method: HTTPMethod { .post }
    var body: (any Encodable & Sendable)? {
        ["amount": amount] as [String: Decimal]
    }
}

// MARK: - Tests

final class NetworkArchitectureTests: XCTestCase {
    
    // MARK: HTTPMethod
    
    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }
    
    // MARK: NetworkError
    
    func testNetworkErrorIsRetryable() {
        XCTAssertTrue(NetworkError.timeout.isRetryable)
        XCTAssertTrue(NetworkError.noConnectivity.isRetryable)
        XCTAssertTrue(NetworkError.serverError(statusCode: 503).isRetryable)
        XCTAssertTrue(NetworkError.tooManyRequests(retryAfter: 5).isRetryable)
        XCTAssertFalse(NetworkError.unauthorized.isRetryable)
        XCTAssertFalse(NetworkError.notFound.isRetryable)
        XCTAssertFalse(NetworkError.decoding(NSError(domain: "", code: 0)).isRetryable)
        XCTAssertFalse(NetworkError.circuitOpen(host: "api.example.com", retryAfter: 30).isRetryable)
    }
    
    func testNetworkErrorMapping() {
        XCTAssertEqual(NetworkError.map(statusCode: 401, data: nil), .unauthorized)
        XCTAssertEqual(NetworkError.map(statusCode: 403, data: nil), .forbidden)
        XCTAssertEqual(NetworkError.map(statusCode: 404, data: nil), .notFound)
        XCTAssertEqual(NetworkError.map(statusCode: 429, data: nil), .tooManyRequests(retryAfter: nil))
        
        if case .serverError(let code) = NetworkError.map(statusCode: 502, data: nil) {
            XCTAssertEqual(code, 502)
        } else {
            XCTFail("Expected serverError")
        }
    }
    
    func testCircuitOpenErrorDescription() {
        let error = NetworkError.circuitOpen(host: "api.example.com", retryAfter: 15)
        XCTAssertTrue(error.localizedDescription.contains("api.example.com"))
        XCTAssertTrue(error.localizedDescription.contains("15"))
    }
    
    // MARK: NetworkConfiguration
    
    func testConfigurationDefaults() {
        let url = URL(string: "https://api.example.com")!
        let config = NetworkConfiguration(baseURL: url)
        
        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.environment, .production)
        XCTAssertEqual(config.timeout, 30)
        XCTAssertTrue(config.waitsForConnectivity)
        XCTAssertFalse(config.defaultHeaders.isEmpty)
        XCTAssertEqual(config.defaultHeaders["Accept"], "application/json")
    }
    
    func testConfigurationCustomInterceptors() {
        let url = URL(string: "https://api.example.com")!
        let config = NetworkConfiguration(
            baseURL: url,
            interceptors: [
                CircuitBreakerInterceptor(),
                IdempotencyInterceptor(),
                LoggingInterceptor(level: .basic)
            ]
        )
        XCTAssertEqual(config.interceptors.count, 3)
    }
    
    // MARK: Endpoint Protocol
    
    func testEndpointDefaults() {
        let endpoint = GetUserEndpoint(id: "42")
        
        XCTAssertEqual(endpoint.path, "/v1/users/42")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertTrue(endpoint.headers.isEmpty)
        XCTAssertNil(endpoint.queryItems)
        XCTAssertNil(endpoint.body)
        XCTAssertNil(endpoint.cachePolicy)
        XCTAssertTrue(endpoint.requiresAuthentication)
        XCTAssertNil(endpoint.idempotencyKey)
    }
    
    func testEndpointWithIdempotencyKey() {
        let key = "payment-abc-123"
        let endpoint = CreatePaymentEndpoint(amount: 49.99, idempotencyKey: key)
        
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.idempotencyKey, key)
        XCTAssertNotNil(endpoint.body)
    }
    
    // MARK: RequestContext
    
    func testRequestContextBasics() {
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        request.httpMethod = "POST"
        
        let context = RequestContext(request: request)
        
        XCTAssertEqual(context.request.url?.absoluteString, "https://api.example.com/test")
        XCTAssertEqual(context.retryCount, 0)
        XCTAssertNil(context.statusCode)
        XCTAssertNil(context.data)
        XCTAssertTrue(context.metadata.isEmpty)
        
        context.metadata["authRefreshed"] = true
        XCTAssertEqual(context.metadata["authRefreshed"] as? Bool, true)
    }
    
    // MARK: IdempotencyInterceptor
    
    func testIdempotencyInterceptorInjectsKeyForPOST() async throws {
        let interceptor = IdempotencyInterceptor()
        var request = URLRequest(url: URL(string: "https://api.example.com/payments")!)
        request.httpMethod = "POST"
        
        let context = RequestContext(request: request)
        try await interceptor.prepare(context)
        
        let key = context.request.value(forHTTPHeaderField: "Idempotency-Key")
        XCTAssertNotNil(key)
        XCTAssertFalse(key!.isEmpty)
        XCTAssertEqual(context.metadata["idempotencyKey"] as? String, key)
    }
    
    func testIdempotencyInterceptorSkipsGET() async throws {
        let interceptor = IdempotencyInterceptor()
        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "GET"
        
        let context = RequestContext(request: request)
        try await interceptor.prepare(context)
        
        XCTAssertNil(context.request.value(forHTTPHeaderField: "Idempotency-Key"))
    }
    
    func testIdempotencyInterceptorRespectsExistingKey() async throws {
        let interceptor = IdempotencyInterceptor()
        var request = URLRequest(url: URL(string: "https://api.example.com/payments")!)
        request.httpMethod = "POST"
        request.setValue("existing-key-999", forHTTPHeaderField: "Idempotency-Key")
        
        let context = RequestContext(request: request)
        try await interceptor.prepare(context)
        
        XCTAssertEqual(context.request.value(forHTTPHeaderField: "Idempotency-Key"), "existing-key-999")
    }
    
    func testIdempotencyInterceptorUsesMetadataKey() async throws {
        let interceptor = IdempotencyInterceptor()
        var request = URLRequest(url: URL(string: "https://api.example.com/payments")!)
        request.httpMethod = "POST"
        
        let context = RequestContext(request: request)
        context.metadata["idempotencyKey"] = "stable-key-from-endpoint"
        try await interceptor.prepare(context)
        
        XCTAssertEqual(context.request.value(forHTTPHeaderField: "Idempotency-Key"), "stable-key-from-endpoint")
    }
    
    // MARK: CircuitBreakerInterceptor
    
    func testCircuitBreakerStartsClosed() async throws {
        let breaker = CircuitBreakerInterceptor(failureThreshold: 3, recoveryTimeout: 10)
        var request = URLRequest(url: URL(string: "https://api.example.com/test")!)
        let context = RequestContext(request: request)
        
        // Should not throw while closed
        try await breaker.prepare(context)
    }
    
    func testCircuitBreakerOpensAfterThreshold() async throws {
        let breaker = CircuitBreakerInterceptor(failureThreshold: 2, recoveryTimeout: 60)
        let url = URL(string: "https://api.example.com/test")!
        
        // Record two failures
        for _ in 0..<2 {
            var request = URLRequest(url: url)
            let context = RequestContext(request: request)
            context.response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
            try await breaker.process(context)
        }
        
        // Next prepare should fail with circuitOpen
        var request = URLRequest(url: url)
        let context = RequestContext(request: request)
        
        do {
            try await breaker.prepare(context)
            XCTFail("Expected circuitOpen error")
        } catch let error as NetworkError {
            if case .circuitOpen(let host, _) = error {
                XCTAssertEqual(host, "api.example.com")
            } else {
                XCTFail("Expected circuitOpen, got \(error)")
            }
        }
    }
    
    func testCircuitBreakerDoesNotTripOn4xx() async throws {
        let breaker = CircuitBreakerInterceptor(failureThreshold: 2, recoveryTimeout: 60)
        let url = URL(string: "https://api.example.com/test")!
        
        // 404 should not count as a failure that trips the circuit
        for _ in 0..<3 {
            var request = URLRequest(url: url)
            let context = RequestContext(request: request)
            context.response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
            try await breaker.process(context)
        }
        
        // Still closed
        var request = URLRequest(url: url)
        let context = RequestContext(request: request)
        try await breaker.prepare(context) // should not throw
    }
    
    // MARK: AuthInterceptor – RefreshRetryPolicy
    
    func testAuthInterceptorInjectsBearerToken() async throws {
        let interceptor = AuthInterceptor(
            tokenProvider: { "test-token-123" }
        )
        
        var request = URLRequest(url: URL(string: "https://api.example.com/me")!)
        let context = RequestContext(request: request)
        
        try await interceptor.prepare(context)
        
        XCTAssertEqual(
            context.request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token-123"
        )
    }
    
    func testAuthInterceptorSingleFlightRefreshSuccess() async throws {
        actor Counter {
            var value = 0
            func increment() -> Int {
                value += 1
                return value
            }
        }
        
        let counter = Counter()
        let interceptor = AuthInterceptor(
            tokenProvider: { nil },
            refreshHandler: {
                _ = await counter.increment()
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                return "new-token"
            },
            refreshRetryPolicy: .none
        )
        
        // Simulate three parallel 401s
        let url = URL(string: "https://api.example.com/data")!
        
        async let first: Void = {
            let ctx = RequestContext(request: URLRequest(url: url))
            ctx.response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
            try await interceptor.process(ctx)
            XCTAssertEqual(ctx.request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
            XCTAssertEqual(ctx.metadata["authRefreshed"] as? Bool, true)
        }()
        
        async let second: Void = {
            let ctx = RequestContext(request: URLRequest(url: url))
            ctx.response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
            try await interceptor.process(ctx)
            XCTAssertEqual(ctx.request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        }()
        
        async let third: Void = {
            let ctx = RequestContext(request: URLRequest(url: url))
            ctx.response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
            try await interceptor.process(ctx)
            XCTAssertEqual(ctx.request.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
        }()
        
        try await first
        try await second
        try await third
        
        // Refresh should have been called only once (single-flight)
        let calls = await counter.value
        XCTAssertEqual(calls, 1)
    }
    
    func testAuthInterceptorRefreshFailureWithNonePolicy() async throws {
        let interceptor = AuthInterceptor(
            tokenProvider: { nil },
            refreshHandler: {
                throw NetworkError.unauthorized
            },
            refreshRetryPolicy: .none
        )
        
        let url = URL(string: "https://api.example.com/data")!
        let context = RequestContext(request: URLRequest(url: url))
        context.response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
        
        do {
            try await interceptor.process(context)
            XCTFail("Expected refresh to throw")
        } catch {
            // Expected – all waiters fail fast
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    // MARK: Sample Integration-style Configuration
    
    func testProductionStyleConfiguration() {
        let config = NetworkConfiguration(
            baseURL: URL(string: "https://api.example.com")!,
            environment: .production,
            timeout: 20,
            interceptors: [
                CircuitBreakerInterceptor(failureThreshold: 5, recoveryTimeout: 30),
                AuthInterceptor(
                    tokenProvider: { "dummy" },
                    refreshHandler: { "refreshed" },
                    refreshRetryPolicy: .once
                ),
                IdempotencyInterceptor(),
                LoggingInterceptor(level: .headers),
                RetryInterceptor(maxAttempts: 3),
                CacheInterceptor(policy: .returnCacheDataElseLoad)
            ]
        )
        
        XCTAssertEqual(config.interceptors.count, 6)
        XCTAssertEqual(config.timeout, 20)
        XCTAssertEqual(config.environment, .production)
        
        // Client can be created without crashing
        let client = NetworkClient(configuration: config)
        XCTAssertNotNil(client)
    }
}
