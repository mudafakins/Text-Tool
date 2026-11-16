import AppKit
import XCTest
@testable import TextToolCore

final class CaseConverterTests: XCTestCase {
    private func convert(_ s: String, _ c: TextCase) -> String { CaseConverter.convert(s, to: c) }

    func testUpperLower() {
        XCTAssertEqual(convert("Hello, World", .upper), "HELLO, WORLD")
        XCTAssertEqual(convert("Hello, World", .lower), "hello, world")
    }

    func testTitleCase() {
        XCTAssertEqual(convert("the lord of the rings", .title), "The Lord of the Rings")
        XCTAssertEqual(convert("WHAT IS THIS FOR", .title), "What Is This For")
        XCTAssertEqual(convert("my new iPhone from NASA", .title), "My New iPhone From NASA")
        XCTAssertEqual(convert("star wars: a new hope", .title), "Star Wars: A New Hope")
        XCTAssertEqual(convert("don't stop me now", .title), "Don't Stop Me Now")
    }

    func testSentenceCase() {
        XCTAssertEqual(convert("HELLO THERE. HOW ARE YOU? i AM FINE!", .sentence),
                       "Hello there. How are you? I am fine!")
        XCTAssertEqual(convert("version 3.5 is OUT now", .sentence), "Version 3.5 is OUT now")
        XCTAssertEqual(convert("first line\nsecond line", .sentence), "First line\nSecond line")
        XCTAssertEqual(convert("i think i'm ready", .sentence), "I think I'm ready")
    }

    func testCamelCase() {
        XCTAssertEqual(convert("hello world", .camel), "helloWorld")
        XCTAssertEqual(convert("User ID number", .camel), "userIdNumber")
        XCTAssertEqual(convert("some_snake_value", .camel), "someSnakeValue")
        XCTAssertEqual(convert("HTTPServer error", .camel), "httpServerError")
        XCTAssertEqual(convert("  first one\n\nsecond-one", .camel), "  firstOne\n\nsecondOne")
    }

    func testSnakeCase() {
        XCTAssertEqual(convert("Hello World", .snake), "hello_world")
        XCTAssertEqual(convert("myVariableName", .snake), "my_variable_name")
        XCTAssertEqual(convert("parseHTTPResponse2Fast", .snake), "parse_http_response2_fast")
        XCTAssertEqual(convert("don't panic!", .snake), "dont_panic")
    }

    func testUnicode() {
        XCTAssertEqual(convert("élan vital", .title), "Élan Vital")
        XCTAssertEqual(convert("straße groß", .snake), "straße_groß")
    }

    func testWordCount() {
        XCTAssertEqual(CaseConverter.wordCount("one two, three."), 3)
    }
}

final class TextRecognizerTests: XCTestCase {
    func testRecognizesRenderedText() async throws {
        let image = Self.render(lines: ["Hello from Text Tool", "Private OCR on device"])
        let text = try await TextRecognizer.recognize(image)
        XCTAssertEqual(text, "Hello from Text Tool\nPrivate OCR on device")
    }

    func testBlankImageThrows() async {
        let image = Self.render(lines: [])
        do {
            _ = try await TextRecognizer.recognize(image)
            XCTFail("Expected noText")
        } catch {}
    }

    static func render(lines: [String]) -> CGImage {
        let size = NSSize(width: 800, height: 240)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
            for (i, line) in lines.enumerated() {
                line.draw(at: NSPoint(x: 30, y: rect.height - 80 - CGFloat(i) * 70), withAttributes: attrs)
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
