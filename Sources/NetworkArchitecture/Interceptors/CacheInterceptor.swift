import Foundation

/// Hybrid caching interceptor.
/// Leverages URLCache for HTTP-compliant caching and an optional in-memory layer
/// for ultra-hot responses (profile, feature flags, etc.).
public struct CacheInterceptor: Interceptor {
    
    public enum Policy: Sendable {
        case ignore
        case returnCacheDataElseLoad
        case returnCacheDataDontLoad
        case reloadIgnoringLocalCacheData
    }
    
    private let policy: Policy
    private let memoryCache: NSCache<NSString, NSData>
    private let memoryTTL: TimeInterval
    
    public init(
        policy: Policy = .returnCacheDataElseLoad,
        memoryCapacity: Int = 50,
        memoryTTL: TimeInterval = 300
    ) {
        self.policy = policy
        self.memoryTTL = memoryTTL
        self.memoryCache = NSCache()
        self.memoryCache.countLimit = memoryCapacity
    }
    
    public func prepare(_ context: RequestContext) async throws {
        guard policy != .ignore, policy != .reloadIgnoringLocalCacheData else { return }
        guard context.request.httpMethod == "GET" else { return }
        
        let key = cacheKey(for: context.request)
        
        // Fast memory hit
        if let cached = memoryCache.object(forKey: key as NSString) {
            context.data = cached as Data
            context.metadata["cacheHit"] = "memory"
            // We still let the request proceed unless DontLoad is set;
            // higher layers can short-circuit if desired.
        }
        
        switch policy {
        case .returnCacheDataDontLoad:
            context.request.cachePolicy = .returnCacheDataDontLoad
        case .returnCacheDataElseLoad:
            context.request.cachePolicy = .returnCacheDataElseLoad
        default:
            break
        }
    }
    
    public func process(_ context: RequestContext) async throws {
        guard policy != .ignore,
              context.request.httpMethod == "GET",
              let data = context.data,
              let status = context.statusCode,
              (200..<300).contains(status) else {
            return
        }
        
        let key = cacheKey(for: context.request)
        memoryCache.setObject(data as NSData, forKey: key as NSString)
    }
    
    private func cacheKey(for request: URLRequest) -> String {
        request.url?.absoluteString ?? UUID().uuidString
    }
}
