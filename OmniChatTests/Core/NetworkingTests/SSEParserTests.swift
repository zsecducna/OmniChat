//
//  SSEParserTests.swift
//  OmniChatTests
//
//  Unit tests for the SSEParser.
//

import Testing
import Foundation
@testable import OmniChat

@Suite("SSEParser Tests")
struct SSEParserTests {

    // MARK: - String Parsing Tests

    @Test("SSEParser parses simple data events")
    func testParseSimpleData() async throws {
        let sseString = """
            data: {"message": "hello"}

            data: {"message": "world"}

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 2)
        #expect(events[0].data == "{\"message\": \"hello\"}")
        #expect(events[1].data == "{\"message\": \"world\"}")
    }

    @Test("SSEParser parses events with event type")
    func testParseEventWithType() async throws {
        let sseString = """
            event: message
            data: {"content": "test"}

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].event == "message")
        #expect(events[0].data == "{\"content\": \"test\"}")
    }

    @Test("SSEParser parses events with ID")
    func testParseEventWithID() async throws {
        let sseString = """
            id: 12345
            data: {"content": "test"}

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].id == "12345")
        #expect(events[0].data == "{\"content\": \"test\"}")
    }

    @Test("SSEParser parses events with retry")
    func testParseEventWithRetry() async throws {
        let sseString = """
            retry: 3000
            data: {"content": "test"}

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].retry == 3000)
    }

    @Test("SSEParser parses multi-line data")
    func testParseMultiLineData() async throws {
        let sseString = """
            data: line one
            data: line two
            data: line three

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].data == "line one\nline two\nline three")
    }

    @Test("SSEParser ignores comments")
    func testParseIgnoresComments() async throws {
        let sseString = """
            : This is a comment
            data: {"content": "test"}
            : Another comment

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].data == "{\"content\": \"test\"}")
    }

    @Test("SSEParser handles CRLF line endings")
    func testParseCRLF() async throws {
        let sseString = "data: {\"test\": \"value\"}\r\n\r\n"

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].data == "{\"test\": \"value\"}")
    }

    @Test("SSEParser handles colon without space")
    func testParseColonNoSpace() async throws {
        let sseString = "data:{\"test\": \"value\"}\n\n"

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].data == "{\"test\": \"value\"}")
    }

    @Test("SSEParser parses OpenAI-style stream")
    func testParseOpenAIStream() async throws {
        let sseString = """
            data: {"choices": [{"delta": {"content": "Hello"}}]}

            data: {"choices": [{"delta": {"content": " world"}}]}

            data: [DONE]

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 3)
        #expect(events[0].data == "{\"choices\": [{\"delta\": {\"content\": \"Hello\"}}]}")
        #expect(events[1].data == "{\"choices\": [{\"delta\": {\"content\": \" world\"}}]}")
        #expect(events[2].data == "[DONE]")
    }

    @Test("SSEParser parses Anthropic-style stream")
    func testParseAnthropicStream() async throws {
        let sseString = """
            event: message_start
            data: {"message": {"id": "msg_123"}}

            event: content_block_delta
            data: {"delta": {"type": "text_delta", "text": "Hello"}}

            event: message_stop
            data: {}

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 3)
        #expect(events[0].event == "message_start")
        #expect(events[1].event == "content_block_delta")
        #expect(events[2].event == "message_stop")
    }

    @Test("SSEParser handles empty input")
    func testParseEmpty() async throws {
        let events = SSEParser.parseString("")
        #expect(events.isEmpty)
    }

    @Test("SSEParser handles only comments")
    func testParseOnlyComments() async throws {
        let sseString = """
            : Comment 1
            : Comment 2

            """

        let events = SSEParser.parseString(sseString)
        #expect(events.isEmpty)
    }

    @Test("SSEParser handles field without value")
    func testParseFieldNoValue() async throws {
        let sseString = """
            event:
            data: test

            """

        let events = SSEParser.parseString(sseString)

        #expect(events.count == 1)
        #expect(events[0].event == "")
        #expect(events[0].data == "test")
    }
}

@Suite("SSEEvent Tests")
struct SSEEventTests {

    @Test("SSEEvent initializes with all fields")
    func testInitialization() async throws {
        let event = SSEEvent(
            event: "message",
            data: "{\"test\": true}",
            id: "123",
            retry: 5000
        )

        #expect(event.event == "message")
        #expect(event.data == "{\"test\": true}")
        #expect(event.id == "123")
        #expect(event.retry == 5000)
    }

    @Test("SSEEvent initializes with defaults")
    func testInitializationDefaults() async throws {
        let event = SSEEvent(data: "test data")

        #expect(event.event == nil)
        #expect(event.data == "test data")
        #expect(event.id == nil)
        #expect(event.retry == nil)
    }

    @Test("SSEEvent dataAsUTF8Data returns correct data")
    func testDataAsUTF8Data() async throws {
        let event = SSEEvent(data: "Hello, World!")
        let data = event.dataAsUTF8Data

        #expect(data != nil)
        #expect(data?.count == 13)

        let string = String(data: data!, encoding: .utf8)
        #expect(string == "Hello, World!")
    }
}

@Suite("SSEParserConfiguration Tests")
struct SSEParserConfigurationTests {

    @Test("SSEParserConfiguration uses default values")
    func testDefaultConfiguration() async throws {
        let config = SSEParserConfiguration.default

        #expect(config.maxDataLength == 1_048_576) // 1MB
        #expect(config.includeComments == false)
    }

    @Test("SSEParserConfiguration accepts custom values")
    func testCustomConfiguration() async throws {
        let config = SSEParserConfiguration(
            maxDataLength: 500_000,
            includeComments: true
        )

        #expect(config.maxDataLength == 500_000)
        #expect(config.includeComments == true)
    }
}

@Suite("SSEParserError Tests")
struct SSEParserErrorTests {

    @Test("SSEParserError descriptions are meaningful")
    func testErrorDescriptions() async throws {
        #expect(SSEParserError.streamInterrupted.description.contains("interrupted"))
        #expect(SSEParserError.invalidUTF8Encoding.description.contains("UTF-8"))
        #expect(SSEParserError.dataExceededMaxLength(maxBytes: 1000).description.contains("1000"))
        #expect(SSEParserError.parsingFailed("test reason").description.contains("test reason"))
    }
}
