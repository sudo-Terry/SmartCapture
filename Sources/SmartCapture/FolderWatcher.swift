import Foundation

/// 저장 폴더의 변화(파일 추가/삭제/이동)를 감지한다.
/// 사용자가 Finder 등에서 캡처를 직접 지우면 이를 감지해 인덱스를 정리하는 데 쓴다.
final class FolderWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.terrykim.smartcapture.folderwatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            NSLog("[SmartCapture] 폴더 감시를 열 수 없습니다: \(url.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],   // 디렉터리 내 항목 변경 시 .write 발생
            queue: queue)
        src.setEventHandler { [weak self] in
            self?.onChange()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
