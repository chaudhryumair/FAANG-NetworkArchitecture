import Foundation

/// Strongly-typed endpoint definition used by FAANG-scale apps.
/// Associate the expected decoded response type to eliminate casting.
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable
    
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem]? { get }
    var body: (any Encodable & Sendable)? { get }
    
    /// Optional cache policy override for this specific endpoint.
    var cachePolicy: URLRequest.CachePolicy? { get }
    
    /// Whether this request should participate in the interceptor chain (default true).
    var requiresAuthentication: Bool { get }
}

public extension Endpoint {
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var cachePolicy: URLRequest.CachePolicy? { nil }
    var requiresAuthentication: Bool { true }
}
