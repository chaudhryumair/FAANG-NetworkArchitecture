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

### Interceptor Order (typical production)

1. **MetricsInterceptor** – start timer / correlate request ID  
2. **AuthInterceptor** – inject Bearer token + handle 401 refresh  
3. **LoggingInterceptor** – structured logs  
4. **CacheInterceptor** – serve from cache or store  
5. **RetryInterceptor** – transient failures  
6. Core request execution

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
        LoggingInterceptor(level: .headers),
        AuthInterceptor(tokenProvider: { await TokenStore.shared.accessToken }),
        RetryInterceptor(maxAttempts: 3),
        CacheInterceptor(policy: .returnCacheDataElseLoad)
    ]
)

// 2. Client
let client = NetworkClient(configuration: config)

// 3. Define Endpoint
struct GetUserEndpoint: Endpoint {
    typealias Response = User
    
    let id: String
    
    var path: String { "/v1/users/\(id)" }
    var method: HTTPMethod { .get }
}

// 4. Execute
let user = try await client.request(GetUserEndpoint(id: "42"))
```

## Core Components

### `Endpoint` Protocol
Strongly typed requests. Associated `Response` removes casting.

### `NetworkClient` (Actor)
Single source of truth. All mutable state is isolated. Safe under Swift 6.

### Interceptors
Composable middleware. Implement `Interceptor` protocol to add your own (rate limiting, feature flags, A/B headers, etc.).

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
    case noConnectivity
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

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/chaudhryumair/FAANG-NetworkArchitecture.git", from: "1.0.0")
```

## License

MIT

---

Built for the top 1% of iOS applications.
