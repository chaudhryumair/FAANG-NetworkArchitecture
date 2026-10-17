import Foundation

/// Injects an `Idempotency-Key` header for non-safe methods.
///
/// - If the endpoint provides an explicit `idempotencyKey`, that value is used.
/// - Otherwise a new UUID is generated for POST / PUT / PATCH / DELETE.
/// - Safe methods (GET, HEAD, OPTIONS) are left untouched.
///
/// This is mandatory for payment flows, ride requests, and any operation
/// that must not be executed twice.
public struct IdempotencyInterceptor: Interceptor {
    
    public init() {}
    
    public func prepare(_ context: RequestContext) async throws {
        let method = context.request.httpMethod?.uppercased() ?? "GET"
        
        // Only non-safe methods need idempotency protection
        let unsafeMethods: Set<String> = ["POST", "PUT", "PATCH", "DELETE"]
        guard unsafeMethods.contains(method) else { return }
        
        // Do not overwrite an existing key
        if context.request.value(forHTTPHeaderField: "Idempotency-Key") != nil {
            return
        }
        
        // Prefer explicit key from metadata (set by higher layers / Endpoint)
        if let explicit = context.metadata["idempotencyKey"] as? String {
            context.request.setValue(explicit, forHTTPHeaderField: "Idempotency-Key")
            return
        }
        
        // Generate a fresh key
        let key = UUID().uuidString
        context.request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        context.metadata["idempotencyKey"] = key
    }
}
