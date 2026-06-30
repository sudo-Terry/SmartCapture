import Foundation

/// 이 앱이 만든 캡처 파일에만 확장 속성(xattr) 표식을 달아 둔다.
/// 정리(휴지통 이동)는 이 표식이 있는 파일만 대상으로 하므로,
/// 같은 폴더에 있는 사용자의 다른 PNG는 절대 건드리지 않는다.
enum FileMarker {
    private static let name = "com.terrykim.smartcapture.managed"

    /// 캡처 파일에 "이 앱이 관리하는 파일" 표식을 단다.
    static func mark(_ url: URL) {
        let value: [UInt8] = [0x31] // "1"
        _ = url.path.withCString { path in
            value.withUnsafeBytes { buf in
                setxattr(path, name, buf.baseAddress, buf.count, 0, 0)
            }
        }
    }

    /// 이 앱이 만든(표식이 있는) 파일인지 확인한다.
    static func isManaged(_ url: URL) -> Bool {
        url.path.withCString { path in
            getxattr(path, name, nil, 0, 0, 0) >= 0
        }
    }

    /// OCR 텍스트를 파일 자체(xattr)에 함께 저장해 정보가 파일을 따라가게 한다.
    static func writeOCR(_ text: String, to url: URL) {
        writeText(text, key: "com.terrykim.smartcapture.ocr", to: url)
    }

    /// VLM 이 생성한 맥락 캡션을 파일 xattr 에 저장한다.
    static func writeCaption(_ text: String, to url: URL) {
        writeText(text, key: "com.terrykim.smartcapture.caption", to: url)
    }

    private static func writeText(_ text: String, key: String, to url: URL) {
        guard !text.isEmpty else { return }
        let bytes = Array(text.utf8)
        _ = url.path.withCString { path in
            bytes.withUnsafeBytes { buf in
                setxattr(path, key, buf.baseAddress, buf.count, 0, 0)
            }
        }
    }
}
