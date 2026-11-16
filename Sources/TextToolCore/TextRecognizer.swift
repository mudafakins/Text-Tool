import CoreGraphics
import Foundation
import Vision

/// On-device OCR using Apple's Vision framework. Nothing leaves the Mac.
public enum TextRecognizer {
    public enum Failure: Error, LocalizedError {
        case noText

        public var errorDescription: String? {
            switch self {
            case .noText: return "No text was found in this image."
            }
        }
    }

    /// Loads Vision's text-recognition models in the background. The first recognition
    /// in a process can take many seconds; after warm-up it takes a fraction of a second.
    public static func warmUp() {
        Task.detached(priority: .utility) {
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            guard let context else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            guard let image = context.makeImage() else { return }
            let request = makeRequest()
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }

    private static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        return request
    }

    /// Recognizes text in an image, returning lines in reading order.
    public static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = makeRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = orderedLines(observations)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Failure.noText }
            return text
        }.value
    }

    /// Sorts observations top-to-bottom, then left-to-right for boxes on the same visual row.
    private static func orderedLines(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let items = observations.compactMap { obs -> (box: CGRect, text: String)? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return (obs.boundingBox, text)
        }
        // Vision uses a bottom-left origin, so larger midY means higher on the page.
        let sorted = items.sorted { a, b in
            let sameRow = abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5
            return sameRow ? a.box.minX < b.box.minX : a.box.midY > b.box.midY
        }
        // Merge boxes on the same row into one line.
        var lines: [(midY: CGFloat, height: CGFloat, text: String)] = []
        for item in sorted {
            if let last = lines.last, abs(last.midY - item.box.midY) < min(last.height, item.box.height) * 0.5 {
                lines[lines.count - 1].text += " " + item.text
            } else {
                lines.append((item.box.midY, item.box.height, item.text))
            }
        }
        return lines.map(\.text)
    }
}
