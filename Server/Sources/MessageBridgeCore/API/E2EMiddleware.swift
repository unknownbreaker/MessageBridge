import Vapor

/// Middleware that handles end-to-end encryption for API responses
/// When the client sends `X-E2E-Encryption: enabled` header, responses will be encrypted.
/// For request decryption, use the Request.decryptedContent() helper.
public struct E2EMiddleware: AsyncMiddleware {
  private let apiKey: String

  public init(apiKey: String) {
    self.apiKey = apiKey
  }

  public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response
  {
    // Check if E2E encryption is requested
    let e2eEnabled = request.headers.first(name: "X-E2E-Encryption") == "enabled"

    // Store API key and E2E flag in request storage for later use
    request.storage[E2EStorageKey.self] = E2EContext(apiKey: apiKey, enabled: e2eEnabled)

    // Get response from next handler
    let response = try await next.respond(to: request)

    // Encrypt response body if E2E is enabled
    if e2eEnabled {
      return try encryptResponse(response, apiKey: apiKey)
    }

    return response
  }

  private func encryptResponse(_ response: Response, apiKey: String) throws -> Response {
    // Get the response body
    guard let body = response.body.buffer else {
      return response
    }

    let bodyData = Data(buffer: body)
    let encryption = E2EEncryption(apiKey: apiKey)

    // Encrypt the body
    let encryptedPayload = try encryption.encrypt(bodyData)

    // Create encrypted envelope
    let envelope = EncryptedEnvelope(version: 1, payload: encryptedPayload)
    let envelopeData = try JSONEncoder().encode(envelope)

    // Create new response with encrypted body
    let newResponse = Response(status: response.status)
    newResponse.headers = response.headers
    newResponse.headers.contentType = .json
    newResponse.headers.add(name: "X-E2E-Encryption", value: "enabled")
    newResponse.body = .init(data: envelopeData)

    return newResponse
  }
}

// MARK: - Request Storage for E2E Context

/// Storage key for E2E encryption context
struct E2EStorageKey: StorageKey {
  typealias Value = E2EContext
}

/// E2E encryption context stored in request
struct E2EContext {
  let apiKey: String
  let enabled: Bool
}

// MARK: - Request Extension for Decrypting Content

extension Request {
  /// Check if E2E encryption is enabled for this request
  public var isE2EEnabled: Bool {
    storage[E2EStorageKey.self]?.enabled ?? false
  }

  /// Decode content, automatically decrypting if E2E is enabled
  public func decryptedContent<T: Decodable>(as type: T.Type) throws -> T {
    guard let context = storage[E2EStorageKey.self], context.enabled else {
      // No E2E, decode normally
      return try content.decode(T.self)
    }

    // Decode the encrypted envelope
    let envelope = try content.decode(EncryptedEnvelope.self)

    guard envelope.version == 1 else {
      throw Abort(.badRequest, reason: "Unsupported encryption version: \(envelope.version)")
    }

    // Decrypt and decode
    let encryption = E2EEncryption(apiKey: context.apiKey)
    return try encryption.decrypt(envelope.payload, as: T.self)
  }
}
