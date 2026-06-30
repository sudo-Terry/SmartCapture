import Foundation
import AppKit
import ImageIO

/// 로컬 Ollama 의 비전-언어 모델(VLM)에 캡처 이미지를 보내,
/// "이 화면이 무슨 맥락인지" 한국어 캡션을 받아온다.
/// 전부 localhost 처리라 외부 전송·API 비용이 없다.
final class VLMService {
    private let endpoint: String   // 예: http://localhost:11434
    private let model: String      // 예: llava:7b
    private let prompt: String

    // 캡처가 몰려도 한 번에 하나씩만 처리(과부하 방지).
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    /// 캡션이 완성되면 (caption, 파일 URL) 으로 호출된다.
    var onCaption: ((String, URL) -> Void)?

    init(endpoint: String, model: String, prompt: String) {
        self.endpoint = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        self.model = model
        self.prompt = prompt
    }

    /// 설치된 Ollama 모델 이름 목록.
    /// nil = 서버에 연결 안 됨(미설치/미기동), [] = 연결됐지만 모델 없음.
    static func installedModels(endpoint: String, timeout: TimeInterval = 1.5) -> [String]? {
        let base = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let url = URL(string: base + "/api/tags") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        var names: [String]?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }
            names = models.compactMap { $0["name"] as? String }
        }.resume()
        semaphore.wait()
        return names
    }

    func enqueue(_ url: URL) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            guard let caption = self.requestCaption(for: url),
                  !caption.isEmpty else { return }
            self.onCaption?(caption, url)
        }
    }

    // MARK: - Ollama 호출

    private func requestCaption(for url: URL) -> String? {
        guard let base64 = downscaledBase64PNG(url) else { return nil }
        guard let reqURL = URL(string: endpoint + "/api/generate") else { return nil }

        var request = URLRequest(url: reqURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "images": [base64],
            "stream": false,
        ])

        var caption: String?
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let error {
                NSLog("[SmartCapture] VLM 연결 실패(서버 꺼짐?): \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            if let response = json["response"] as? String {
                caption = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let err = json["error"] as? String {
                NSLog("[SmartCapture] VLM 오류: \(err) (모델 받았는지 확인: ollama pull \(self.model))")
            }
        }
        task.resume()
        semaphore.wait()
        return caption
    }

    /// 속도/토큰 절약을 위해 긴 변 1024px 로 축소한 PNG 를 base64 로 변환.
    private func downscaledBase64PNG(_ url: URL, maxPixel: CGFloat = 1024) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
