import AppKit

/// macOS 기본 `/usr/sbin/screencapture` 를 감싸 다양한 캡처 모드를 제공한다.
final class ScreenshotService {

    enum Mode {
        case fullScreen   // 전체 화면 즉시 캡처
        case region       // 영역 선택 (스페이스바로 창 모드 전환 가능)
        case window       // 창 선택 모드

        var arguments: [String] {
            switch self {
            case .fullScreen: return []
            case .region:     return ["-i"]
            case .window:     return ["-iW"]
            }
        }
    }

    private let config: Config
    /// 캡처가 끝나면 (성공 시 파일 URL) 메인 스레드에서 호출된다.
    var onCaptured: ((URL) -> Void)?
    /// 권한 등으로 캡처가 실패해 파일이 안 생겼을 때 메인 스레드에서 호출된다.
    var onPermissionError: ((String) -> Void)?

    init(config: Config) {
        self.config = config
    }

    func capture(_ mode: Mode) {
        let url = makeFileURL()
        var args = mode.arguments
        if !config.playSound { args.append("-x") }   // -x: 소리 끄기
        args.append(url.path)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            let errPipe = Pipe()
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("[SmartCapture] screencapture 실행 실패: \(error)")
                return
            }

            let errText = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? ""

            // 파일이 안 생긴 경우: 권한 문제인지 / 단순 취소인지 구분.
            guard FileManager.default.fileExists(atPath: url.path) else {
                let lower = errText.lowercased()
                if lower.contains("could not create image")
                    || lower.contains("not authorized")
                    || lower.contains("cannot") {
                    NSLog("[SmartCapture] 캡처 실패(권한 의심): \(errText)")
                    DispatchQueue.main.async {
                        self.onPermissionError?(errText.isEmpty ? "화면 기록 권한이 필요합니다." : errText)
                    }
                }
                // errText 가 비고 파일도 없으면 사용자가 Esc로 취소한 것 → 조용히 무시.
                return
            }

            // 이 앱이 만든 파일임을 표식해 둔다 (정리 시 이 파일만 대상으로 함).
            FileMarker.mark(url)

            DispatchQueue.main.async {
                self.copyToClipboard(url)
                self.onCaptured?(url)
            }
        }
    }

    /// 캡처 이미지를 클립보드에 복사해 바로 붙여넣을 수 있게 한다.
    private func copyToClipboard(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // PNG 원본 데이터 + NSImage 둘 다 올려 호환성을 높인다.
        pasteboard.setData(data, forType: .png)
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
    }

    private func makeFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: Date())).png"
        return config.saveDirectory.appendingPathComponent(name)
    }
}
