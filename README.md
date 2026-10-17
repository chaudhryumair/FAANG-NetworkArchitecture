# FAANG-Level Network Architecture

**Production-grade, zero-dependency networking layer used by top 1% iOS apps.**

Built with modern Swift 6 concurrency, actor isolation, and an interceptor middleware architecture inspired by systems running at Netflix, Uber, Airbnb, and similar scale.

## Features

| Feature | Status |
|---------|--------|
| Swift 6 Strict Concurrency | ✅ |
| Actor-isolated client | ✅ |
| Interceptor / Middleware chain | ✅ |
| Typed Endpoints + Generics | ✅ |
| Async/Await only | ✅ |
| Exponential backoff + jitter + `Retry-After` | ✅ |
| Single-flight Token Refresh | ✅ |
| Configurable Refresh Retry Policy (`.none` / `.once`) | ✅ |
| **Automatic retry after successful token refresh** | ✅ |
| **Circuit Breaker** | ✅ |
| **Idempotency-Key support** | ✅ |
| Hybrid Caching (Memory + URLCache) | ✅ |
| Comprehensive typed errors | ✅ |
| Configurable environments | ✅ |
| Logging levels (basic → body) | ✅ |
| Metrics / Observability hooks | ✅ |
| Certificate Pinning ready | ✅ |
| Zero third-party dependencies | ✅ |
| Fully testable / mockable | ✅ |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     NetworkClient (Actor)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Interceptors│→ │ URLSession  │→ │ Response Validation │  │
│  │  (Chain)    │  │             │  │ + Decoding          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         ▲
         │
   ┌─────┴─────┐
   │ Endpoints │  (protocol + associatedtype Response)
   └───────────┘
```

### Recommended Interceptor Order (production)

1. **MetricsInterceptor** – start timer / correlate request ID  
2. **CircuitBreakerInterceptor** – fail fast when a host is unhealthy  
3. **AuthInterceptor** – inject Bearer token + handle 401 refresh  
4. **IdempotencyInterceptor** – protect non-safe methods  
5. **LoggingInterceptor** – structured logs  
6. **CacheInterceptor** – serve from cache or store  
7. **RetryInterceptor** – transient failures  
8. Core request execution

## Quick Start

```swift
import NetworkArchitecture

// 1. Configuration
let config = NetworkConfiguration(
    baseURL: URL(string: "https://api.example.com")!,
    environment: .production,
    defaultHeaders: [
        "Accept": "application/json",
        "Content-Type": "application/json"
    ],
    timeout: 30,
    interceptors: [
        MetricsInterceptor { metric in
            // Forward to your observability backend
        },
        CircuitBreakerInterceptor(failureThreshold: 5, recoveryTimeout: 30),
        AuthInterceptor(
            tokenProvider: { await TokenStore.shared.accessToken },
            refreshHandler: { try await TokenStore.shared.refresh() },
            refreshRetryPolicy: .once
        ),
        IdempotencyInterceptor(),
        LoggingInterceptor(level: .headers),
        RetryInterceptor(maxAttempts: 3),
        CacheInterceptor(policy: .returnCacheDataElseLoad)
    ]
)

// 2. Client
let client = NetworkClient(configuration: config)

// 3. Define Endpoint (with optional stable idempotency key)
struct CreatePaymentEndpoint: Endpoint {
    typealias Response = Payment
    
    let amount: Decimal
    let idempotencyKey: String?   // stable across retries
    
    var path: String { "/v1/payments" }
    var method: HTTPMethod { .post }
    var body: (any Encodable & Sendable)? { ["amount": amount] }
}

// 4. Execute – token refresh + original request retry is automatic
let payment = try await client.request(
    CreatePaymentEndpoint(amount: 49.99, idempotencyKey: UUID().uuidString)
)
```

## Core Components

### `Endpoint` Protocol
Strongly typed requests. Associated `Response` removes casting.  
Supports optional `idempotencyKey` for payment / ride-request safety.

### `NetworkClient` (Actor)
Single source of truth. All mutable state is isolated. Safe under Swift 6.  
**Automatically re-executes the original request once after a successful token refresh.**

### AuthInterceptor & RefreshRetryPolicy

```swift
public enum RefreshRetryPolicy: Sendable {
    case none   // fail fast (default)
    case once   // retry the refresh exactly once
}
```

- Multiple concurrent 401s share one refresh `Task` (single-flight).
- On successful refresh the original request is transparently retried once.

### CircuitBreakerInterceptor

Tracks consecutive failures per host:

- **Closed** → normal traffic
- **Open** → fail fast for `recoveryTimeout`
- **Half-open** → allow limited probes, then close or re-open

Throws `NetworkError.circuitOpen(host:retryAfter:)` while open.

### IdempotencyInterceptor

- Automatically injects `Idempotency-Key` for POST / PUT / PATCH / DELETE.
- Uses `Endpoint.idempotencyKey` when provided (recommended for payments).
- Otherwise generates a UUID.

### Error Model
```swift
enum NetworkError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decoding(Error)
    case transport(URLError)
    case cancelled
    case unauthorized
    case circuitOpen(host: String, retryAfter: TimeInterval)
    // ...
}
```

## Production Recommendations

- Always inject a real `URLSession` configuration with proper `URLCache`, `waitsForConnectivity`, and timeout values.
- Use background `URLSession` only for large downloads / uploads.
- Prefer `async let` / `TaskGroup` for parallel independent requests.
- Keep interceptors pure and side-effect free where possible.
- Add certificate pinning in security-sensitive apps via custom `URLSessionDelegate`.
- Instrument with your observability stack (Datadog, New Relic, Firebase Performance, custom) via `MetricsInterceptor`.
- For payment / ride apps always supply a stable `idempotencyKey` on the Endpoint.

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/chaudhryumair/FAANG-NetworkArchitecture.git", from: "1.0.0")
```

## License

MIT

---

Built for the top 1% of iOS applications.
