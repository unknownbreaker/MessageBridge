import Vapor

/// Middleware that validates API key authentication via X-API-Key header
public struct APIKeyMiddleware: AsyncMiddleware {
  private let validAPIKey: String

  public init(apiKey: String) {
    self.validAPIKey = apiKey
  }

  public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response
  {
    guard let providedKey = request.headers.first(name: "X-API-Key") else {
      throw Abort(.unauthorized, reason: "Missing API key")
    }

    guard providedKey == validAPIKey else {
      throw Abort(.unauthorized, reason: "Invalid API key")
    }

    return try await next.respond(to: request)
  }
}
