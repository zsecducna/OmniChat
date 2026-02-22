//
//  AttachmentTests.swift
//  OmniChatTests
//
//  Unit tests for the Attachment model and AttachmentManager.
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import OmniChat

@Suite("Attachment Model Tests")
struct AttachmentTests {

    // MARK: - Initialization Tests

    @Test("Attachment initializes with all values")
    func testInitialization() async throws {
        let data = "test content".data(using: .utf8)!
        let thumbnail = "thumbnail".data(using: .utf8)!

        let attachment = Attachment(
            fileName: "test.txt",
            mimeType: "text/plain",
            data: data,
            thumbnailData: thumbnail
        )

        #expect(attachment.fileName == "test.txt")
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.data == data)
        #expect(attachment.thumbnailData == thumbnail)
    }

    @Test("Attachment initializes with default values")
    func testInitializationDefaults() async throws {
        let attachment = Attachment(
            fileName: "test.png",
            mimeType: "image/png",
            data: Data()
        )

        #expect(attachment.thumbnailData == nil)
        #expect(attachment.message == nil)
    }

    // MARK: - Computed Properties Tests

    @Test("Attachment fileExtension extracts correctly")
    func testFileExtension() async throws {
        let png = Attachment(fileName: "image.PNG", mimeType: "image/png", data: Data())
        #expect(png.fileExtension == "png")

        let txt = Attachment(fileName: "document.txt", mimeType: "text/plain", data: Data())
        #expect(txt.fileExtension == "txt")

        let noExt = Attachment(fileName: "noextension", mimeType: "text/plain", data: Data())
        #expect(noExt.fileExtension == "")
    }

    @Test("Attachment isImage detects image MIME types")
    func testIsImage() async throws {
        let png = Attachment(fileName: "test", mimeType: "image/png", data: Data())
        #expect(png.isImage == true)

        let jpeg = Attachment(fileName: "test", mimeType: "image/jpeg", data: Data())
        #expect(jpeg.isImage == true)

        let text = Attachment(fileName: "test", mimeType: "text/plain", data: Data())
        #expect(text.isImage == false)
    }

    @Test("Attachment supportsThumbnail detects supported types")
    func testSupportsThumbnail() async throws {
        let jpeg = Attachment(fileName: "test", mimeType: "image/jpeg", data: Data())
        #expect(jpeg.supportsThumbnail == true)

        let png = Attachment(fileName: "test", mimeType: "image/png", data: Data())
        #expect(png.supportsThumbnail == true)

        let gif = Attachment(fileName: "test", mimeType: "image/gif", data: Data())
        #expect(gif.supportsThumbnail == true)

        let bmp = Attachment(fileName: "test", mimeType: "image/bmp", data: Data())
        #expect(bmp.supportsThumbnail == true)

        let pdf = Attachment(fileName: "test", mimeType: "application/pdf", data: Data())
        #expect(pdf.supportsThumbnail == false)
    }

    @Test("Attachment fileSize returns correct size")
    func testFileSize() async throws {
        let data = Data(repeating: 0, count: 1024)
        let attachment = Attachment(fileName: "test", mimeType: "application/octet-stream", data: data)

        #expect(attachment.fileSize == 1024)
    }

    @Test("Attachment fileSizeDescription formats correctly")
    func testFileSizeDescription() async throws {
        let small = Attachment(fileName: "test", mimeType: "text/plain", data: Data(repeating: 0, count: 500))
        #expect(small.fileSizeDescription.contains("500"))

        let kb = Attachment(fileName: "test", mimeType: "text/plain", data: Data(repeating: 0, count: 2048))
        #expect(kb.fileSizeDescription.contains("KB"))
    }

    @Test("Attachment isLargeForSync detects large files")
    func testIsLargeForSync() async throws {
        let small = Attachment(fileName: "test", mimeType: "text/plain", data: Data(repeating: 0, count: 1024))
        #expect(small.isLargeForSync == false)

        let large = Attachment(fileName: "test", mimeType: "text/plain", data: Data(repeating: 0, count: 2 * 1024 * 1024))
        #expect(large.isLargeForSync == true)
    }

    @Test("Attachment utType returns correct type")
    func testUTType() async throws {
        let png = Attachment(fileName: "test.png", mimeType: "image/png", data: Data())
        #expect(png.utType == .png)

        let txt = Attachment(fileName: "test.txt", mimeType: "text/plain", data: Data())
        #expect(txt.utType == .text)
    }
}

@Suite("AttachmentManager Tests")
struct AttachmentManagerTests {

    // MARK: - MIME Type Helpers Tests

    @Test("AttachmentManager supportsThumbnail detects image types")
    func testSupportsThumbnail() async throws {
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/jpeg") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/png") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/gif") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/heic") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/webp") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "image/bmp") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "application/pdf") == false)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "text/plain") == false)
    }

    @Test("AttachmentManager supportsThumbnail is case insensitive")
    func testSupportsThumbnailCaseInsensitive() async throws {
        #expect(AttachmentManager.supportsThumbnail(mimeType: "IMAGE/JPEG") == true)
        #expect(AttachmentManager.supportsThumbnail(mimeType: "Image/Png") == true)
    }

    @Test("AttachmentManager isImage detects image types")
    func testIsImage() async throws {
        #expect(AttachmentManager.isImage(mimeType: "image/jpeg") == true)
        #expect(AttachmentManager.isImage(mimeType: "image/png") == true)
        #expect(AttachmentManager.isImage(mimeType: "application/pdf") == false)
        #expect(AttachmentManager.isImage(mimeType: "text/plain") == false)
    }

    @Test("AttachmentManager isImage is case insensitive")
    func testIsImageCaseInsensitive() async throws {
        #expect(AttachmentManager.isImage(mimeType: "IMAGE/JPEG") == true)
        #expect(AttachmentManager.isImage(mimeType: "Image/png") == true)
    }

    // MARK: - Size Utilities Tests

    @Test("AttachmentManager formatFileSize formats correctly")
    func testFormatFileSize() async throws {
        #expect(AttachmentManager.formatFileSize(500).contains("500"))
        #expect(AttachmentManager.formatFileSize(1024).contains("KB"))
        #expect(AttachmentManager.formatFileSize(1024 * 1024).contains("MB"))
    }

    @Test("AttachmentManager isLargeAttachment detects large files")
    func testIsLargeAttachment() async throws {
        #expect(AttachmentManager.isLargeAttachment(500 * 1024) == false) // 500KB
        #expect(AttachmentManager.isLargeAttachment(1 * 1024 * 1024) == false) // 1MB (boundary)
        #expect(AttachmentManager.isLargeAttachment(2 * 1024 * 1024) == true) // 2MB
    }

    // MARK: - Attachment Creation Tests

    @Test("AttachmentManager createAttachment creates attachment without thumbnail for non-images")
    func testCreateAttachmentNonImage() async throws {
        let data = "test content".data(using: .utf8)!

        let attachment = AttachmentManager.createAttachment(
            fileName: "test.txt",
            mimeType: "text/plain",
            data: data
        )

        #expect(attachment.fileName == "test.txt")
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.data == data)
        #expect(attachment.thumbnailData == nil)
    }

    @Test("AttachmentManager createAttachment skips thumbnail when disabled")
    func testCreateAttachmentSkipThumbnail() async throws {
        let data = "test content".data(using: .utf8)!

        let attachment = AttachmentManager.createAttachment(
            fileName: "test.png",
            mimeType: "image/png",
            data: data,
            generateThumbnail: false
        )

        #expect(attachment.thumbnailData == nil)
    }

    // MARK: - Constants Tests

    @Test("AttachmentManager constants are correct")
    func testConstants() async throws {
        #expect(AttachmentManager.defaultThumbnailSize == CGSize(width: 200, height: 200))
        #expect(AttachmentManager.maxThumbnailFileSize == 50 * 1024)
        #expect(AttachmentManager.thumbnailCompressionQuality == 0.7)
    }
}
