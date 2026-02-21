//
//  Attachment.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData

@Model
final class Attachment {
    var id: UUID
    var fileName: String
    var mimeType: String
    var data: Data
    var thumbnailData: Data?
    var createdAt: Date

    var message: Message?

    init(
        id: UUID = UUID(),
        fileName: String,
        mimeType: String,
        data: Data,
        thumbnailData: Data? = nil,
        createdAt: Date = Date(),
        message: Message? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.message = message
    }
}
