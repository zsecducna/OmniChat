//
//  AttachmentPicker.swift
//  OmniChat
//
//  File and image picker component for message attachments.
//  Supports PhotosPicker for images and fileImporter for documents.
//  Raycast-inspired dense UI with compression settings for images.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os

// MARK: - Logger

private let logger = Logger(subsystem: "com.omnichatt.app", category: "AttachmentPicker")

// MARK: - AttachmentPicker

/// Unified picker for images and file attachments.
///
/// This component provides:
/// - PhotosPicker for image selection (iOS/macOS)
/// - FileImporter for document selection
/// - Automatic image compression for large images
/// - Attachment preview with remove functionality
///
/// ## Usage
/// ```swift
/// @State private var attachments: [AttachmentPayload] = []
///
/// VStack {
///     AttachmentPreviewList(attachments: attachments) { index in
///         attachments.remove(at: index)
///     }
///
///     AttachmentPicker(attachments: $attachments)
/// }
/// ```
@MainActor
struct AttachmentPicker: View {
    // MARK: - Properties

    /// The array of attachments being edited.
    @Binding var attachments: [AttachmentPayload]

    /// Maximum dimension for image compression (default: 2048px).
    var maxImageDimension: CGFloat = 2048

    /// JPEG compression quality (default: 0.7).
    var compressionQuality: CGFloat = 0.7

    /// Maximum file size in bytes (default: 20MB).
    var maxFileSize: Int = 20 * 1024 * 1024

    // MARK: - State

    /// Selected photo item from PhotosPicker.
    @State private var selectedItem: PhotosPickerItem?

    /// Controls presentation of file importer.
    @State private var showFileImporter = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: Theme.Spacing.medium.rawValue) {
            // Image picker button
            PhotosPicker(selection: $selectedItem, matching: .images) {
                VStack(spacing: Theme.Spacing.tight.rawValue) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Photo")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(width: 60, height: 60)
                .background(Theme.Colors.tertiaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .onChange(of: selectedItem) { _, item in
                if let item = item {
                    loadImage(from: item)
                }
            }

            // File importer button
            Button {
                showFileImporter = true
            } label: {
                VStack(spacing: Theme.Spacing.tight.rawValue) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.accent)
                    Text("File")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(width: 60, height: 60)
                .background(Theme.Colors.tertiaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium.rawValue)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Allowed Content Types

    /// Supported file types for document import.
    private var allowedContentTypes: [UTType] {
        [
            .pdf,
            .plainText,
            .json,
            .html,
            .xml,
            .rtf,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "swift") ?? .sourceCode,
            UTType(filenameExtension: "py") ?? .sourceCode,
            UTType(filenameExtension: "js") ?? .sourceCode,
            UTType(filenameExtension: "ts") ?? .sourceCode,
            UTType(filenameExtension: "tsx") ?? .sourceCode,
            UTType(filenameExtension: "jsx") ?? .sourceCode,
            UTType(filenameExtension: "java") ?? .sourceCode,
            UTType(filenameExtension: "kt") ?? .sourceCode,
            UTType(filenameExtension: "go") ?? .sourceCode,
            UTType(filenameExtension: "rs") ?? .sourceCode,
            UTType(filenameExtension: "c") ?? .sourceCode,
            UTType(filenameExtension: "cpp") ?? .sourceCode,
            UTType(filenameExtension: "h") ?? .sourceCode,
            UTType(filenameExtension: "cs") ?? .sourceCode,
            UTType(filenameExtension: "rb") ?? .sourceCode,
            UTType(filenameExtension: "php") ?? .sourceCode,
            UTType(filenameExtension: "css") ?? .sourceCode,
            UTType(filenameExtension: "scss") ?? .sourceCode,
            UTType(filenameExtension: "sql") ?? .sourceCode,
            UTType(filenameExtension: "sh") ?? .sourceCode,
            UTType(filenameExtension: "yaml") ?? .sourceCode,
            UTType(filenameExtension: "yml") ?? .sourceCode,
            UTType(filenameExtension: "toml") ?? .sourceCode,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText,
            UTType(filenameExtension: "txt") ?? .plainText,
        ]
    }

    // MARK: - Image Loading

    /// Loads and compresses an image from PhotosPicker selection.
    private func loadImage(from item: PhotosPickerItem) {
        Task {
            do {
                // Load data from the photo item
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    logger.warning("Failed to load image data from picker")
                    return
                }

                // Get filename extension from content type
                let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let fileName = "image.\(fileExtension)"

                // Check file size
                guard data.count <= maxFileSize else {
                    logger.warning("Image file too large: \(data.count) bytes")
                    return
                }

                // Compress the image
                let compressedData = compressImage(data)

                // Determine MIME type
                let mimeType = mimeTypeFor(extension: fileExtension)

                // Create attachment
                let attachment = AttachmentPayload(
                    data: compressedData,
                    mimeType: mimeType,
                    fileName: fileName
                )

                await MainActor.run {
                    attachments.append(attachment)
                    selectedItem = nil
                }

                logger.info("Image attached: \(fileName), size: \(compressedData.count) bytes")
            } catch {
                logger.error("Failed to load image: \(error.localizedDescription)")
            }
        }
    }

    /// Compresses image data if needed.
    private func compressImage(_ data: Data) -> Data {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else {
            logger.warning("Could not create UIImage from data, returning original")
            return data
        }

        // Calculate scale factor for resizing
        let maxDimension = maxImageDimension
        let scale = min(
            maxDimension / uiImage.size.width,
            maxDimension / uiImage.size.height,
            1.0 // Don't upscale
        )

        // Only resize if needed
        guard scale < 1.0 else {
            // Just compress without resizing
            return uiImage.jpegData(compressionQuality: compressionQuality) ?? data
        }

        // Resize the image
        let newSize = CGSize(
            width: uiImage.size.width * scale,
            height: uiImage.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedData = renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }

        logger.info("Image compressed: \(data.count) -> \(resizedData.count) bytes")
        return resizedData

        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else {
            logger.warning("Could not create NSImage from data, returning original")
            return data
        }

        // Get the bitmap representation
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            logger.warning("Could not create bitmap representation, returning original")
            return data
        }

        // Calculate new size if needed
        let currentSize = nsImage.size
        let scale = min(
            maxImageDimension / currentSize.width,
            maxImageDimension / currentSize.height,
            1.0
        )

        // Resize if needed
        if scale < 1.0 {
            let newSize = NSSize(
                width: currentSize.width * scale,
                height: currentSize.height * scale
            )

            let resizedImage = NSImage(size: newSize)
            resizedImage.lockFocus()
            nsImage.draw(in: NSRect(origin: .zero, size: newSize))
            resizedImage.unlockFocus()

            if let resizedTiff = resizedImage.tiffRepresentation,
               let resizedBitmap = NSBitmapImageRep(data: resizedTiff),
               let compressedData = resizedBitmap.representation(
                   using: .jpeg,
                   properties: [.compressionFactor: compressionQuality]
               ) {
                logger.info("Image compressed: \(data.count) -> \(compressedData.count) bytes")
                return compressedData
            }
        }

        // Just compress without resizing
        if let compressedData = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        ) {
            logger.info("Image compressed: \(data.count) -> \(compressedData.count) bytes")
            return compressedData
        }

        return data
        #else
        return data
        #endif
    }

    // MARK: - File Import

    /// Handles file import result.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importFile(from: url)
            }

        case .failure(let error):
            logger.error("File import failed: \(error.localizedDescription)")
        }
    }

    /// Imports a file from URL.
    private func importFile(from url: URL) {
        // Request access to security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            logger.warning("Could not access security-scoped resource: \(url.path)")
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        do {
            // Read file data
            let data = try Data(contentsOf: url)

            // Check file size
            guard data.count <= maxFileSize else {
                logger.warning("File too large: \(url.lastPathComponent), \(data.count) bytes")
                return
            }

            // Determine MIME type
            let mimeType = mimeTypeFor(url: url)

            // Create attachment
            let attachment = AttachmentPayload(
                data: data,
                mimeType: mimeType,
                fileName: url.lastPathComponent
            )

            attachments.append(attachment)
            logger.info("File attached: \(url.lastPathComponent), size: \(data.count) bytes")

        } catch {
            logger.error("Failed to read file: \(error.localizedDescription)")
        }
    }

    // MARK: - MIME Type Helpers

    /// Returns MIME type for a file URL.
    private func mimeTypeFor(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return mimeTypeFor(extension: ext)
    }

    /// Returns MIME type for a file extension.
    private func mimeTypeFor(extension ext: String) -> String {
        switch ext {
        // Images
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "bmp":
            return "image/bmp"
        case "tiff", "tif":
            return "image/tiff"

        // Documents
        case "pdf":
            return "application/pdf"

        // Text formats
        case "txt", "md", "markdown":
            return "text/plain"
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "csv":
            return "text/csv"
        case "rtf":
            return "text/rtf"
        case "xml":
            return "text/xml"

        // Data formats
        case "json":
            return "application/json"
        case "yaml", "yml":
            return "text/yaml"
        case "toml":
            return "text/x-toml"

        // Code files
        case "swift":
            return "text/x-swift"
        case "py":
            return "text/x-python"
        case "js":
            return "text/javascript"
        case "ts":
            return "text/typescript"
        case "jsx":
            return "text/jsx"
        case "tsx":
            return "text/tsx"
        case "java":
            return "text/x-java"
        case "kt", "kts":
            return "text/x-kotlin"
        case "go":
            return "text/x-go"
        case "rs":
            return "text/x-rust"
        case "c":
            return "text/x-c"
        case "cpp", "cc", "cxx":
            return "text/x-c++"
        case "h", "hpp":
            return "text/x-c-header"
        case "cs":
            return "text/x-csharp"
        case "rb":
            return "text/x-ruby"
        case "php":
            return "text/x-php"
        case "sql":
            return "text/x-sql"
        case "sh", "bash", "zsh":
            return "text/x-sh"

        // Shell/config
        default:
            // Try to use UTType
            if let utType = UTType(filenameExtension: ext),
               let mimeType = utType.preferredMIMEType {
                return mimeType
            }
            return "application/octet-stream"
        }
    }
}

// MARK: - AttachmentPreview

/// Preview view for a single attachment.
///
/// Shows a thumbnail for images or an icon for documents,
/// along with filename, size, and a remove button.
@MainActor
struct AttachmentPreview: View {
    // MARK: - Properties

    /// The attachment to preview.
    let attachment: AttachmentPayload

    /// Action called when the user removes the attachment.
    let onRemove: () -> Void

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            // Thumbnail or icon
            thumbnailView

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            Spacer()

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, Theme.Spacing.small.rawValue)
        .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
        .background(Theme.Colors.tertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue))
    }

    // MARK: - Subviews

    /// Thumbnail view - shows image preview or document icon.
    @ViewBuilder
    private var thumbnailView: some View {
        if attachment.mimeType.hasPrefix("image/") {
            imageView
        } else {
            documentIcon
        }
    }

    /// Image thumbnail for image attachments.
    @ViewBuilder
    private var imageView: some View {
        #if os(iOS)
        if let uiImage = UIImage(data: attachment.data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue))
        } else {
            documentIcon
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: attachment.data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue))
        } else {
            documentIcon
        }
        #else
        documentIcon
        #endif
    }

    /// Document icon for non-image attachments.
    private var documentIcon: some View {
        Image(systemName: iconForMimeType)
            .font(.system(size: 16))
            .foregroundStyle(Theme.Colors.tertiaryText)
            .frame(width: 32, height: 32)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.small.rawValue))
    }

    /// Returns an appropriate SF Symbol for the MIME type.
    private var iconForMimeType: String {
        let mime = attachment.mimeType.lowercased()

        if mime.hasPrefix("image/") {
            return "photo"
        } else if mime == "application/pdf" {
            return "doc.richtext"
        } else if mime.hasPrefix("text/") {
            if mime.contains("x-swift") || mime.contains("x-python") ||
               mime.contains("javascript") || mime.contains("x-") {
                return "chevron.left.forwardslash.chevron.right"
            }
            return "doc.text"
        } else if mime == "application/json" {
            return "curlybraces"
        } else {
            return "doc"
        }
    }
}

// MARK: - AttachmentPreviewList

/// Horizontal scrollable list of attachment previews.
///
/// Displays multiple attachments with the ability to remove each.
@MainActor
struct AttachmentPreviewList: View {
    // MARK: - Properties

    /// The array of attachments to display.
    let attachments: [AttachmentPayload]

    /// Action called when an attachment is removed.
    let onRemove: (Int) -> Void

    // MARK: - Body

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.small.rawValue) {
                    ForEach(Array(attachments.enumerated()), id: \.element.fileName) { index, attachment in
                        AttachmentPreview(attachment: attachment) {
                            onRemove(index)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Theme.Spacing.small.rawValue)
                .padding(.vertical, Theme.Spacing.extraSmall.rawValue)
            }
            .frame(height: 48)
        }
    }
}

// MARK: - CompactAttachmentPicker

/// Compact inline picker with just icons (for use in message input bar).
///
/// Shows only icon buttons without labels for a denser UI.
@MainActor
struct CompactAttachmentPicker: View {
    // MARK: - Properties

    /// The array of attachments being edited.
    @Binding var attachments: [AttachmentPayload]

    /// Maximum dimension for image compression.
    var maxImageDimension: CGFloat = 2048

    /// JPEG compression quality.
    var compressionQuality: CGFloat = 0.7

    /// Maximum file size in bytes.
    var maxFileSize: Int = 20 * 1024 * 1024

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFileImporter = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: Theme.Spacing.small.rawValue) {
            // Image picker
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            .onChange(of: selectedItem) { _, item in
                if let item = item {
                    loadImage(from: item)
                }
            }

            // File importer
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Allowed Content Types

    private var allowedContentTypes: [UTType] {
        [
            .pdf, .plainText, .json, .html,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "swift") ?? .sourceCode,
            UTType(filenameExtension: "py") ?? .sourceCode,
            UTType(filenameExtension: "js") ?? .sourceCode,
            UTType(filenameExtension: "ts") ?? .sourceCode,
        ]
    }

    // MARK: - Image Loading

    private func loadImage(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }

            guard data.count <= maxFileSize else {
                return
            }

            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let compressedData = compressImage(data)
            let mimeType = mimeTypeFor(extension: fileExtension)

            let attachment = AttachmentPayload(
                data: compressedData,
                mimeType: mimeType,
                fileName: "image.\(fileExtension)"
            )

            await MainActor.run {
                attachments.append(attachment)
                selectedItem = nil
            }
        }
    }

    private func compressImage(_ data: Data) -> Data {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return data }

        let scale = min(maxImageDimension / uiImage.size.width, maxImageDimension / uiImage.size.height, 1.0)
        let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { context in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let compressed = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) else {
            return data
        }
        return compressed
        #else
        return data
        #endif
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                if let data = try? Data(contentsOf: url), data.count <= maxFileSize {
                    let attachment = AttachmentPayload(
                        data: data,
                        mimeType: mimeTypeFor(url: url),
                        fileName: url.lastPathComponent
                    )
                    attachments.append(attachment)
                }
            }
        case .failure:
            break
        }
    }

    private func mimeTypeFor(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return mimeTypeFor(extension: ext)
    }

    private func mimeTypeFor(extension ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "txt", "md": return "text/plain"
        case "json": return "application/json"
        case "html": return "text/html"
        case "swift": return "text/x-swift"
        case "py": return "text/x-python"
        case "js": return "text/javascript"
        case "ts": return "text/typescript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Previews

#Preview("Attachment Picker") {
    VStack(spacing: Theme.Spacing.large.rawValue) {
        AttachmentPicker(attachments: .constant([]))
    }
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Attachment Preview - Image") {
    AttachmentPreview(
        attachment: AttachmentPayload(
            data: Data(repeating: 0, count: 1024 * 512), // 512KB
            mimeType: "image/png",
            fileName: "screenshot.png"
        ),
        onRemove: { print("Remove") }
    )
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Attachment Preview - Document") {
    AttachmentPreview(
        attachment: AttachmentPayload(
            data: Data(repeating: 0, count: 1024 * 128), // 128KB
            mimeType: "application/pdf",
            fileName: "document.pdf"
        ),
        onRemove: { print("Remove") }
    )
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Attachment Preview - Code") {
    AttachmentPreview(
        attachment: AttachmentPayload(
            data: Data(repeating: 0, count: 2048), // 2KB
            mimeType: "text/x-swift",
            fileName: "ContentView.swift"
        ),
        onRemove: { print("Remove") }
    )
    .padding()
    .background(Theme.Colors.background)
}

#Preview("Attachment Preview List") {
    VStack {
        AttachmentPreviewList(
            attachments: [
                AttachmentPayload(data: Data(repeating: 0, count: 1024 * 512), mimeType: "image/png", fileName: "screenshot.png"),
                AttachmentPayload(data: Data(repeating: 0, count: 1024 * 128), mimeType: "application/pdf", fileName: "document.pdf"),
                AttachmentPayload(data: Data(repeating: 0, count: 2048), mimeType: "text/x-swift", fileName: "ContentView.swift"),
                AttachmentPayload(data: Data(repeating: 0, count: 1024), mimeType: "text/x-python", fileName: "script.py"),
            ]
        ) { index in
            print("Remove at \(index)")
        }

        Spacer()
    }
    .background(Theme.Colors.background)
}

#Preview("Compact Attachment Picker") {
    HStack {
        CompactAttachmentPicker(attachments: .constant([]))
        Spacer()
    }
    .padding()
    .background(Theme.Colors.background)
}
