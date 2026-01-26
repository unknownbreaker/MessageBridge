import Vapor

/// Configures all API routes for the application
public func configureRoutes(
  _ app: Application, database: ChatDatabaseProtocol, messageSender: MessageSenderProtocol,
  apiKey: String, webSocketManager: WebSocketManager? = nil
) throws {
  // Health check - no authentication required
  app.get("health") { _ in
    HealthResponse()
  }

  // Protected routes - require API key and support E2E encryption
  let protected = app.grouped(APIKeyMiddleware(apiKey: apiKey))
    .grouped(E2EMiddleware(apiKey: apiKey))

  // GET /conversations - List all conversations (paginated)
  protected.get("conversations") { req async throws -> ConversationsResponse in
    let limit = req.query[Int.self, at: "limit"] ?? 50
    let offset = req.query[Int.self, at: "offset"] ?? 0

    do {
      let conversations = try await database.fetchRecentConversations(limit: limit, offset: offset)
      let nextCursor = conversations.count == limit ? String(offset + limit) : nil
      return ConversationsResponse(conversations: conversations, nextCursor: nextCursor)
    } catch {
      throw Abort(.internalServerError, reason: "Failed to fetch conversations")
    }
  }

  // GET /conversations/:id/messages - Messages for a conversation (paginated)
  protected.get("conversations", ":id", "messages") { req async throws -> MessagesResponse in
    guard let conversationId = req.parameters.get("id") else {
      throw Abort(.badRequest, reason: "Missing conversation ID")
    }

    let limit = req.query[Int.self, at: "limit"] ?? 50
    let offset = req.query[Int.self, at: "offset"] ?? 0

    do {
      let messages = try await database.fetchMessages(
        conversationId: conversationId, limit: limit, offset: offset)
      let processedMessages = messages.map { ProcessorChain.shared.process($0) }
      let nextCursor = messages.count == limit ? String(offset + limit) : nil
      return MessagesResponse(messages: processedMessages, nextCursor: nextCursor)
    } catch {
      throw Abort(.internalServerError, reason: "Failed to fetch messages")
    }
  }

  // POST /conversations/:id/read - Mark conversation as read
  protected.post("conversations", ":id", "read") { req async throws -> HTTPStatus in
    guard let conversationId = req.parameters.get("id") else {
      throw Abort(.badRequest, reason: "Missing conversation ID")
    }

    do {
      try await database.markConversationAsRead(conversationId: conversationId)
      return .ok
    } catch {
      throw Abort(.internalServerError, reason: "Failed to mark conversation as read")
    }
  }

  // GET /search?q= - Search messages by content
  protected.get("search") { req async throws -> SearchResponse in
    guard let query = req.query[String.self, at: "q"], !query.isEmpty else {
      throw Abort(.badRequest, reason: "Missing or empty search query")
    }

    let limit = req.query[Int.self, at: "limit"] ?? 50

    do {
      let messages = try await database.searchMessages(query: query, limit: limit)
      let processedMessages = messages.map { ProcessorChain.shared.process($0) }
      return SearchResponse(messages: processedMessages, query: query)
    } catch {
      throw Abort(.internalServerError, reason: "Failed to search messages")
    }
  }

  // GET /attachments/:id - Serve attachment file
  protected.get("attachments", ":id") { req async throws -> Response in
    guard let idString = req.parameters.get("id"),
      let attachmentId = Int64(idString)
    else {
      throw Abort(.badRequest, reason: "Invalid attachment ID")
    }

    do {
      guard let result = try await database.fetchAttachment(id: attachmentId) else {
        throw Abort(.notFound, reason: "Attachment not found")
      }

      let (attachment, filePath) = result

      // Check if file exists
      guard FileManager.default.fileExists(atPath: filePath) else {
        throw Abort(.notFound, reason: "Attachment file not found")
      }

      // Determine content type
      let contentType: HTTPMediaType
      if let mimeType = attachment.mimeType {
        contentType = HTTPMediaType(
          type: String(mimeType.split(separator: "/").first ?? "application"),
          subType: String(mimeType.split(separator: "/").last ?? "octet-stream")
        )
      } else {
        contentType = .binary
      }

      // Stream the file
      let response = req.fileio.streamFile(at: filePath)
      response.headers.contentType = contentType
      response.headers.add(
        name: .contentDisposition, value: "inline; filename=\"\(attachment.filename)\"")

      return response
    } catch let abort as Abort {
      throw abort
    } catch {
      throw Abort(.internalServerError, reason: "Failed to fetch attachment")
    }
  }

  // POST /send - Send a message
  protected.post("send") { req async throws -> SendResponse in
    let sendRequest: SendMessageRequest
    do {
      // Use decryptedContent to handle both encrypted and unencrypted requests
      sendRequest = try req.decryptedContent(as: SendMessageRequest.self)
    } catch {
      throw Abort(.badRequest, reason: "Invalid request body")
    }

    guard !sendRequest.to.isEmpty else {
      throw Abort(.badRequest, reason: "Recipient cannot be empty")
    }

    guard !sendRequest.text.isEmpty else {
      throw Abort(.badRequest, reason: "Message text cannot be empty")
    }

    do {
      let result = try await messageSender.sendMessage(
        to: sendRequest.to,
        text: sendRequest.text,
        service: sendRequest.service
      )
      return SendResponse(from: result)
    } catch {
      throw Abort(
        .internalServerError, reason: "Failed to send message: \(error.localizedDescription)")
    }
  }

  // WebSocket endpoint for real-time updates
  if let wsManager = webSocketManager {
    app.webSocket("ws") { req, ws in
      // Validate API key from query parameter or header
      let providedKey = req.query[String.self, at: "apiKey"] ?? req.headers.first(name: "X-API-Key")

      guard providedKey == apiKey else {
        _ = ws.close(code: .policyViolation)
        return
      }

      // Check if E2E encryption is requested
      let e2eEnabled =
        req.query[String.self, at: "e2e"] == "enabled"
        || req.headers.first(name: "X-E2E-Encryption") == "enabled"

      // Add connection with E2E encryption if requested
      Task {
        let connectionId = await wsManager.addConnection(
          ws,
          apiKey: e2eEnabled ? apiKey : nil,
          e2eEnabled: e2eEnabled
        )
        await wsManager.sendConnected(to: connectionId)

        // Handle disconnect
        ws.onClose.whenComplete { _ in
          Task {
            await wsManager.removeConnection(connectionId)
          }
        }
      }

      // Handle incoming text messages (for future use)
      ws.onText { ws, text in
        // Could handle client commands here in the future
        _ = text
      }
    }
  }
}
