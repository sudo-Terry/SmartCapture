import AppKit

/// 저장 디렉터리를 주기적으로 훑어, 보관 기간이 지난 캡처를 휴지통으로 옮긴다.
/// (영구 삭제가 아니라 휴지통 이동이라 실수해도 복구 가능하다.)
final class CleanupService {
    private let config: Config
    private var timer: Timer?

    /// 파일을 휴지통으로 옮긴 직후 호출된다(검색 인덱스 정리용).
    var onRemoved: ((String) -> Void)?

    init(config: Config) {
        self.config = config
    }

    func start() {
        // 시작 직후 한 번, 이후 주기적으로 실행.
        cleanupNow()
        let t = Timer.scheduledTimer(
            withTimeInterval: config.cleanupIntervalSeconds, repeats: true
        ) { [weak self] _ in
            self?.cleanupNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 보관 기간이 지난 png 파일을 휴지통으로 이동. 반환값은 이동된 개수.
    @discardableResult
    func cleanupNow() -> Int {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(config.retentionDays) * 86_400)
        guard let items = try? fm.contentsOfDirectory(
            at: config.saveDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var moved = 0
        for url in items where url.pathExtension.lowercased() == "png" {
            // 이 앱이 만든(표식이 있는) 파일만 정리한다. 사용자의 다른 PNG는 건너뛴다.
            guard FileMarker.isManaged(url) else { continue }
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate,
                  modified < cutoff else { continue }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                onRemoved?(url.path)
                moved += 1
            } catch {
                NSLog("[SmartCapture] 휴지통 이동 실패: \(url.lastPathComponent) - \(error)")
            }
        }
        if moved > 0 {
            NSLog("[SmartCapture] 오래된 캡처 \(moved)개를 휴지통으로 이동했습니다.")
        }
        return moved
    }
}
