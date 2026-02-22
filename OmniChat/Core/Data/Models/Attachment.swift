//
//  Attachment.swift
//  OmniChat
//
//  Created by Claude on 2026-02-21.
//

import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers
import os

/// SwiftData model for storing file and image attachments in chat messages.
///
/// Attachments are synced via CloudKit along with their parent messages.
/// For optimal sync performance:
/// - Thumbnails are generated for images (max 200x200)
/// - Thumbnail data is stored separately from full attachment data
/// - UI can display thumbnails without downloading full attachments
///
/// ## Example
///
/// ```swift
/// // Create an attachment with auto-generated thumbnail
/// let attachment = Attachment(
///     fileName: "screenshot.png",
///     mimeType: "image/png",
///     data: imageData
/// )
/// attachment.generateThumbnail()
///
/// // Check if attachment is an image
/// if attachment.isImage {
///     // Show image preview using thumbnail
/// }
/// ```
@Model
final class Attachment {
    // MARK: - Stored Properties

    /// Unique identifier for the attachment.
    var id: UUID = UUID()

    /// Original filename of the attachment.
    var fileName: String = ""

    /// MIME type of the attachment (e.g., "image/png", "application/pdf").
    var mimeType: String = "application/octet-stream"

    /// Full attachment data (synced via CloudKit).
    var data: Data = Data()

    /// Cached thumbnail for images (max 200x200, JPEG format).
    ///
    /// Thumbnails are automatically generated for images when
    /// `generateThumbnail()` is called. They are synced separately
    /// from full attachment data for efficient list display.
    var thumbnailData: Data?

    /// Timestamp when the attachment was created.
    var createdAt: Date = Date()

    // MARK: - Relationships

    /// The message this attachment belongs to.
    var message: Message?

    // MARK: - Initialization

    /// Creates a new attachment.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID).
    ///   - fileName: Original filename.
    ///   - mimeType: MIME type of the content.
    ///   - data: Full attachment data.
    ///   - thumbnailData: Optional pre-generated thumbnail.
    ///   - createdAt: Creation timestamp (defaults to now).
    ///   - message: Parent message (set when added to a message).
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

    // MARK: - Computed Properties

    /// Returns the file extension from the filename.
    var fileExtension: String {
        return (fileName as NSString).pathExtension.lowercased()
    }

    /// Returns the Uniform Type Identifier for this attachment.
    var utType: UTType? {
        if let type = UTType(filenameExtension: fileExtension) {
            return type
        }
        // Fallback to MIME type
        return UTType(mimeType: mimeType)
    }

    /// Checks if this attachment is an image.
    var isImage: Bool {
        return mimeType.lowercased().hasPrefix("image/")
    }

    /// Checks if this attachment supports thumbnail generation.
    var supportsThumbnail: Bool {
        let supportedTypes = [
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/heic",
            "image/heif",
            "image/webp",
            "image/tiff",
            "image/bmp"
        ]
        return supportedTypes.contains(mimeType.lowercased())
    }

    /// Returns the file size in bytes.
    var fileSize: Int {
        return data.count
    }

    /// Returns a human-readable file size description.
    var fileSizeDescription: String {
        return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    /// Checks if this attachment is considered large for CloudKit sync (>1MB).
    var isLargeForSync: Bool {
        return data.count > 1 * 1024 * 1024
    }

    // MARK: - Thumbnail Generation

    /// Generates and stores a thumbnail for this attachment if it's an image.
    ///
    /// Uses ImageIO for cross-platform thumbnail generation that works on both
    /// iOS and macOS. The thumbnail is scaled proportionally to fit within
    /// the maximum size while preserving aspect ratio.
    ///
    /// - Parameter maxSize: Maximum dimensions for the thumbnail (default: 200x200).
    /// - Returns: True if a thumbnail was generated, false otherwise.
    @discardableResult
    func generateThumbnail(maxSize: CGSize = CGSize(width: 200, height: 200)) -> Bool {
        let logger = Logger(subsystem: "com.yourname.omnichat", category: "Attachment")

        guard thumbnailData == nil else {
            // Thumbnail already exists
            logger.debug("Thumbnail already exists for attachment: \(self.fileName)")
            return true
        }

        guard supportsThumbnail else {
            logger.debug("Attachment does not support thumbnails: \(self.mimeType)")
            return false
        }

        // Create an image source from the data
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            logger.warning("Failed to create image source from data")
            return false
        }

        // Check if the image source contains an image
        guard CGImageSourceGetCount(imageSource) > 0 else {
            logger.warning("Image source contains no images")
            return false
        }

        // Set up thumbnail options
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,  // Preserve orientation
            kCGImageSourceCreateThumbnailFromImageAlways: true,  // Always create thumbnail
            kCGImageSourceThumbnailMaxPixelSize: max(maxSize.width, maxSize.height)  // Max dimension
        ]

        // Generate the thumbnail
        guard let thumbnailRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            logger.warning("Failed to create thumbnail from image source")
            return false
        }

        // Create a destination for JPEG output
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            logger.warning("Failed to create image destination")
            return false
        }

        // Set JPEG compression quality
        let compressionQuality: CGFloat = 0.7
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        // Add the thumbnail to the destination
        CGImageDestinationAddImage(destination, thumbnailRef, destinationOptions as CFDictionary)
        CGImageDestinationFinalize(destination)

        let generatedThumbnailData = outputData as Data

        // Verify the thumbnail is within size limits (50KB max)
        if generatedThumbnailData.count <= 50 * 1024 {
            thumbnailData = generatedThumbnailData
            logger.info("Generated thumbnail for \(self.fileName): \(generatedThumbnailData.count) bytes")
            return true
        }

        // Compress further if needed
        if let compressed = compressThumbnail(thumbnailRef, targetSize: 50 * 1024, logger: logger) {
            thumbnailData = compressed
            logger.info("Generated compressed thumbnail for \(self.fileName): \(compressed.count) bytes")
            return true
        }

        logger.warning("Failed to compress thumbnail for \(self.fileName)")
        return false
    }

    /// Compresses a thumbnail image to meet target file size.
    private func compressThumbnail(_ imageRef: CGImage, targetSize: Int, logger: Logger) -> Data? {
        var quality: CGFloat = 0.7
        var compressedData: Data?

        // Iteratively reduce quality until we meet the size limit
        while quality > 0.1 {
            let outputData = NSMutableData()

            guard let destination = CGImageDestinationCreateWithData(
                outputData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                break
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]

            CGImageDestinationAddImage(destination, imageRef, options as CFDictionary)
            CGImageDestinationFinalize(destination)

            let data = outputData as Data

            if data.count <= targetSize {
                compressedData = data
                break
            }

            quality -= 0.1
        }

        return compressedData
    }
}
