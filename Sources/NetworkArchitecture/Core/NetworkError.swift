import Foundation

/// Comprehensive typed error taxonomy used by top-tier production apps.
public enum NetworkError: Error, Sendable, LocalizedError {
    case invalidURL
    case invalidRequest
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decoding(Error)
    case encoding(Error)
    case transport(URLError)
    case cancelled
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case tooManyRequests(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case noConnectivity
    case timeout
    case certificatePinningFailed
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL provided was invalid."
        case .invalidRequest:
            return "The request could not be constructed."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpError(let code, _):
            return "HTTP error with status code \(code)."
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encoding(let error):
            return "Failed to encode request body: \(error.localizedDescription)"
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        case .cancelled:
            return "The request was cancelled."
        case .unauthorized:
            return "Authentication required."
        case .forbidden:
            return "Access forbidden."
        case .notFound:
            return "Resource not found."
        case .conflict:
            return "Resource conflict."
        case .tooManyRequests(let retryAfter):
            if let retryAfter {
                return "Too many requests. Retry after \(retryAfter) seconds."
            }
            return "Too many requests."
        case .serverError(let code):
            return "Server error (\(code))."
        case .noConnectivity:
            return "No network connectivity."
        case .timeout:
            return "The request timed out."
        case .certificatePinningFailed:
            return "Certificate pinning validation failed."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
    
    /// Whether the error is potentially recoverable with a retry.
    public var isRetryable: Bool {
        switch self {
        case .transport(let urlError):
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                return false
            }
        case .timeout, .noConnectivity, .tooManyRequests, .serverError:
            return true
        case .httpError(let code, _):
            return [408, 429, 500, 502, 503, 504].contains(code)
        default:
            return false
        }
    }
    
    public static func map(statusCode: Int, data: Data?) -> NetworkError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict
        case 429: return .tooManyRequests(retryAfter: nil)
        case 500...599: return .serverError(statusCode: statusCode)
        default: return .httpError(statusCode: statusCode, data: data)
        }
    }
}
