import Vision
import AppKit

/// 캡처 이미지의 의미 정보를 추출한다.
/// 모두 Apple Vision(온디바이스, Neural Engine) 기반이라 외부 의존성·비용이 없다.
struct ImageAnalysis {
    var ocrText: String      // 이미지 속 글자 (스크린샷 검색의 핵심)
    var tags: [String]       // 장면/객체 분류 라벨
    var embedding: [Float]   // 특징 벡터 (유사 이미지 검색용)
}

enum ImageAnalyzer {

    static func analyze(_ url: URL) -> ImageAnalysis {
        let handler = VNImageRequestHandler(url: url, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["ko-KR", "en-US"]

        let classifyRequest = VNClassifyImageRequest()
        let featureRequest = VNGenerateImageFeaturePrintRequest()

        do {
            // 한 번의 핸들러 호출로 세 가지 분석을 함께 수행한다.
            try handler.perform([textRequest, classifyRequest, featureRequest])
        } catch {
            NSLog("[SmartCapture] 이미지 분석 실패: \(error)")
        }

        let ocr = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        let tags = (classifyRequest.results ?? [])
            .filter { $0.confidence > 0.15 }
            .prefix(8)
            .map { $0.identifier }

        var embedding: [Float] = []
        if let fp = featureRequest.results?.first {
            embedding = fp.floatArray()
        }

        return ImageAnalysis(ocrText: ocr, tags: Array(tags), embedding: embedding)
    }
}

private extension VNFeaturePrintObservation {
    /// 특징 벡터 Data 를 [Float] 로 변환한다.
    func floatArray() -> [Float] {
        guard elementType == .float,
              data.count == elementCount * MemoryLayout<Float>.size else { return [] }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(elementCount))
        }
    }
}
