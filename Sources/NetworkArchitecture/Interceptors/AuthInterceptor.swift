import Foundation

/// Token provider closure. Must be Sendable and async-safe.
public typealias TokenProvider = @Sendable () async throws -> String?

/// Production Auth interceptor with single-flight refresh support.
/// Prevents thundering-herd of simultaneous refresh calls.
public actor AuthInterceptor: Interceptor {
    
    private let tokenProvider: TokenProvider
    private let refreshHandler: (@Sendable () async throws -> String)?
    private var refreshTask: Task<String, Error>?
    
    public init(
        tokenProvider: @escaping TokenProvider,
        refreshHandler: (@Sendable () async throws -> String)? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
    }
    
    nonisolated public func prepare(_ context: RequestContext) async throws {
        // We need to hop into the actor to access state
        try await self._prepare(context)
    }
    
    nonisolated public func process(_ context: RequestContext) async throws {
        try await self._process(context)
    }
    
    private func _prepare(_ context: RequestContext) async throws {
        if let token = try await tokenProvider() {
            context.request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    private func _process(_ context: RequestContext) async throws {
        guard context.statusCode == 401,
              let refreshHandler else {
            return
        }
        
        // Single-flight refresh
        let token: String
        if let existing = refreshTask {
            token = try await existing.value
        } else {
            let task = Task {
                try await refreshHandler()
            }
            refreshTask = task
            defer { refreshTask = nil }
            token = try await task.value
        }
        
        // Update the request so a higher-level retry can reuse it
        context.request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        context.metadata["authRefreshed"] = true
    }
}
