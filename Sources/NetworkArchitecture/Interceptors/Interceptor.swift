import Foundation

/// Middleware protocol used by every major production networking stack.
/// Interceptors form a chain-of-responsibility that can mutate requests,
/// short-circuit, retry, log, cache, refresh tokens, emit metrics, etc.
public protocol Interceptor: Sendable {
    /// Called before the request is sent. Modify `context.request` or throw.
    func prepare(_ context: RequestContext) async throws
    
    /// Called after a response is received (or an error occurs).
    /// You may mutate context, decide to retry, or transform the error.
    func process(_ context: RequestContext) async throws
}

public extension Interceptor {
    func prepare(_ context: RequestContext) async throws {}
    func process(_ context: RequestContext) async throws {}
}
