import Foundation

/// Sanitized provider/runtime failures safe to surface or log by case.
///
/// The enum intentionally carries no raw response body, request body, URL query, or credential.
public enum AIProviderError: Error, Sendable, Equatable {
    case configurationMismatch
    case credentialMissing
    case invalidCredential
    case insufficientPermission
    case billingUnavailable
    case rateLimited(retryAfterSeconds: Double?)
    case invalidRequest
    case modelUnavailable
    case unsupportedCapability
    case serviceUnavailable
    case networkUnavailable
    case invalidProviderResponse
    case cancelled
}

extension AIProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configurationMismatch:
            "The provider configuration does not match this adapter."
        case .credentialMissing:
            "An API key is required."
        case .invalidCredential:
            "The API key was not accepted."
        case .insufficientPermission:
            "The API key does not have the required permission."
        case .billingUnavailable:
            "The provider account cannot currently make paid requests."
        case .rateLimited:
            "The provider rate or quota limit was reached."
        case .invalidRequest:
            "The provider rejected the request."
        case .modelUnavailable:
            "The selected model is not available."
        case .unsupportedCapability:
            "This provider adapter does not support the requested capability."
        case .serviceUnavailable:
            "The provider service is temporarily unavailable."
        case .networkUnavailable:
            "The provider could not be reached."
        case .invalidProviderResponse:
            "The provider returned an unexpected response."
        case .cancelled:
            "The request was cancelled."
        }
    }
}

/// Result of validating a provider configuration without issuing a paid completion.
public enum AIProviderValidationOutcome: Sendable, Equatable {
    case valid(models: [AIModelDescriptor])
    case credentialMissing
    case invalidCredential
    case insufficientPermission
    case billingUnavailable
    case rateLimited(retryAfterSeconds: Double?)
    case unavailable
    case misconfigured
}
