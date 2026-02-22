//
//  AttachmentManager.swift
//  OmniChat
//
//  Created by Claude on 2026-02-22.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// Manages attachment operations including thumbnail generation and optimization.
///
/// This manager provides utilities for:
/// - Generating thumbnails for images (cross-platform via ImageIO)
/// - Determining if attachments should have thumbnails
/// - Optimizing attachments for CloudKit sync
///
/// ## CloudKit Optimization
///
/// For optimal CloudKit sync performance:
/// - Large attachments use CloudKit assets for Data fields
/// - Thumbnails are generated for images (max 200x200) for list views
/// - Thumbnails are synced separately from full attachment data
/// - UI can display thumbnails without downloading full attachments
///
/// ## Usage
///
/// ```swift
/// // Generate a thumbnail for an image
/// if let thumbnail = AttachmentManager.generateThumbnail(from: imageData, maxSize: CGSize(width: 200, height: 200)) {
///     attachment.thumbnailData = thumbnail
/// }
///
/// // Check if MIME type supports thumbnails
/// if AttachmentManager.supportsThumbnail(mimeType: "image/png") {
///     // Generate thumbnail
/// }
/// ```
enum AttachmentManager: Sendable {
    // MARK: - Constants

    /// Default maximum thumbnail size (200x200 pixels).
    static let defaultThumbnailSize = CGSize(width: 200, height: 200)

    /// Maximum thumbnail file size (50KB) - kept small for efficient sync.
    static let maxThumbnailFileSize = 50 * 1024

    /// JPEG compression quality for thumbnails.
    static let thumbnailCompressionQuality: CGFloat = 0.7

    // MARK: - Logger

    private static let logger = Logger(subsystem: "com.yourname.omnichat", category: "AttachmentManager")

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail from image data.
    ///
    /// Uses ImageIO for cross-platform thumbnail generation that works on both
    /// iOS and macOS. The thumbnail is scaled proportionally to fit within
    /// the maximum size while preserving aspect ratio.
    ///
    /// - Parameters:
    ///   - imageData: The original image data (PNG, JPEG, GIF, HEIC, etc.)
    ///   - maxSize: Maximum dimensions for the thumbnail (default: 200x200)
    /// - Returns: Compressed JPEG thumbnail data, or nil if generation fails.
    ///
    /// - Note: Returns nil for non-image data or if image cannot be decoded.
    ///         The thumbnail is always returned as JPEG for consistent file size.
    static func generateThumbnail(from imageData: Data, maxSize: CGSize = defaultThumbnailSize) -> Data? {
        // Create an image source from the data
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            logger.warning("Failed to create image source from data")
            return nil
        }

        // Check if the image source contains an image
        guard CGImageSourceGetCount(imageSource) > 0 else {
            logger.warning("Image source contains no images")
            return nil
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
            return nil
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
            return nil
        }

        // Set JPEG compression quality
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: thumbnailCompressionQuality
        ]

        // Add the thumbnail to the destination
        CGImageDestinationAddImage(destination, thumbnailRef, destinationOptions as CFDictionary)
        CGImageDestinationFinalize(destination)

        let thumbnailData = outputData as Data

        // Verify the thumbnail is within size limits
        if thumbnailData.count > maxThumbnailFileSize {
            logger.info("Thumbnail exceeds size limit: \(thumbnailData.count) bytes, attempting further compression")
            return compressThumbnail(thumbnailRef, targetSize: maxThumbnailFileSize)
        }

        logger.info("Generated thumbnail: \(thumbnailData.count) bytes, size: \(thumbnailRef.width)x\(thumbnailRef.height)")
        return thumbnailData
    }

    /// Compresses a thumbnail image to meet target file size.
    ///
    /// - Parameters:
    ///   - imageRef: The CGImage to compress.
    ///   - targetSize: Target file size in bytes.
    /// - Returns: Compressed JPEG data, or nil if compression fails.
    private static func compressThumbnail(_ imageRef: CGImage, targetSize: Int) -> Data? {
        var quality = thumbnailCompressionQuality
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
                logger.info("Compressed thumbnail to \(data.count) bytes at quality \(quality)")
                break
            }

            quality -= 0.1
        }

        return compressedData
    }

    // MARK: - MIME Type Helpers

    /// Checks if a MIME type supports thumbnail generation.
    ///
    /// - Parameter mimeType: The MIME type to check.
    /// - Returns: True if the MIME type is an image that supports thumbnailing.
    static func supportsThumbnail(mimeType: String) -> Bool {
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

    /// Checks if a MIME type indicates an image.
    ///
    /// - Parameter mimeType: The MIME type to check.
    /// - Returns: True if the MIME type starts with "image/".
    static func isImage(mimeType: String) -> Bool {
        return mimeType.lowercased().hasPrefix("image/")
    }

    // MARK: - Attachment Creation

    /// Creates an Attachment with an automatically generated thumbnail.
    ///
    /// If the attachment is an image and supports thumbnails, this method
    /// will generate and attach a thumbnail.
    ///
    /// - Parameters:
    ///   - fileName: The original filename.
    ///   - mimeType: The MIME type of the attachment.
    ///   - data: The attachment data.
    ///   - generateThumbnail: Whether to generate a thumbnail for images (default: true).
    /// - Returns: An Attachment model with optional thumbnail data.
    ///
    /// - Note: This method does NOT save the attachment to SwiftData.
    ///         The caller is responsible for inserting it into a model context.
    static func createAttachment(
        fileName: String,
        mimeType: String,
        data: Data,
        generateThumbnail: Bool = true
    ) -> Attachment {
        var thumbnailData: Data? = nil

        if generateThumbnail && supportsThumbnail(mimeType: mimeType) {
            thumbnailData = Self.generateThumbnail(from: data)
        }

        return Attachment(
            fileName: fileName,
            mimeType: mimeType,
            data: data,
            thumbnailData: thumbnailData
        )
    }

    // MARK: - Size Utilities

    /// Returns a human-readable file size description.
    ///
    /// - Parameter byteCount: The number of bytes.
    /// - Returns: A formatted string (e.g., "1.5 MB").
    static func formatFileSize(_ byteCount: Int) -> String {
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// Checks if an attachment size is considered large for CloudKit sync.
    ///
    /// CloudKit has optimal performance with smaller assets. Attachments
    /// larger than this threshold may benefit from alternative sync strategies.
    ///
    /// - Parameter byteCount: The number of bytes.
    /// - Returns: True if the attachment is considered large (>1MB).
    static func isLargeAttachment(_ byteCount: Int) -> Bool {
        return byteCount > 1 * 1024 * 1024  // > 1MB
    }
}
