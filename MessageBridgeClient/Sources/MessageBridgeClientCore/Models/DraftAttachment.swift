import Foundation

/// A draft attachment queued for sending, not yet uploaded.
public struct DraftAttachment: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let type: AttachmentType
    public let fileName: String

    public init(id: String = UUID().uuidString, url: URL, type: AttachmentType, fileName: String) {
        self.id = id
        self.url = url
        self.type = type
        self.fileName = fileName
    }
}
