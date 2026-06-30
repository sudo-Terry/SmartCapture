import Foundation

/// 앱 설정. 기본값을 사용하되, 있으면
/// ~/Library/Application Support/SmartCapture/config.json 으로 덮어쓴다.
struct Config {
    var saveDirectory: URL
    var retentionDays: Int            // 며칠 지난 캡처를 휴지통으로 옮길지
    var cleanupIntervalSeconds: TimeInterval
    var playSound: Bool               // 캡처 시 셔터음 재생 여부
    var previewSeconds: TimeInterval  // 미리보기 썸네일이 떠 있는 시간

    // 로컬 VLM(이미지 맥락 해석) — 기본 꺼짐. Ollama 필요.
    var vlmEnabled: Bool
    var vlmEndpoint: String
    var vlmModel: String
    var vlmPrompt: String

    static let appSupportDir: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SmartCapture", isDirectory: true)
    }()

    static var configFileURL: URL {
        appSupportDir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        let defaultDir = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ScreenShots", isDirectory: true)

        var config = Config(
            saveDirectory: defaultDir,
            retentionDays: 7,
            cleanupIntervalSeconds: 3600,   // 1시간마다 정리
            playSound: true,
            previewSeconds: 6,
            vlmEnabled: false,
            vlmEndpoint: "http://localhost:11434",
            vlmModel: "llava:7b",
            vlmPrompt: "이 스크린샷에 무엇이 보이는지 한국어로 한두 문장으로 요약해줘. 어떤 앱/화면인지, 핵심 주제와 검색에 쓸 키워드를 포함해줘. 설명만 출력해."
        )

        if let data = try? Data(contentsOf: configFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let dir = json["saveDirectory"] as? String, !dir.isEmpty {
                let expanded = (dir as NSString).expandingTildeInPath
                config.saveDirectory = URL(fileURLWithPath: expanded, isDirectory: true)
            }
            if let v = json["retentionDays"] as? Int { config.retentionDays = v }
            if let v = json["cleanupIntervalSeconds"] as? Double { config.cleanupIntervalSeconds = v }
            if let v = json["playSound"] as? Bool { config.playSound = v }
            if let v = json["previewSeconds"] as? Double { config.previewSeconds = v }
            if let v = json["vlmEnabled"] as? Bool { config.vlmEnabled = v }
            if let v = json["vlmEndpoint"] as? String, !v.isEmpty { config.vlmEndpoint = v }
            if let v = json["vlmModel"] as? String, !v.isEmpty { config.vlmModel = v }
            if let v = json["vlmPrompt"] as? String, !v.isEmpty { config.vlmPrompt = v }
        }

        try? FileManager.default.createDirectory(
            at: config.saveDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: appSupportDir, withIntermediateDirectories: true)

        // 설정 파일이 없으면 기본값으로 한 벌 생성해 사용자가 편집할 수 있게 한다.
        if !FileManager.default.fileExists(atPath: configFileURL.path) {
            config.save()
        }
        return config
    }

    /// 현재 설정을 config.json 에 기록한다(메뉴에서 토글/모델 변경 시 호출).
    func save() {
        let dict: [String: Any] = [
            "saveDirectory": saveDirectory.path,
            "retentionDays": retentionDays,
            "cleanupIntervalSeconds": cleanupIntervalSeconds,
            "playSound": playSound,
            "previewSeconds": previewSeconds,
            "vlmEnabled": vlmEnabled,
            "vlmEndpoint": vlmEndpoint,
            "vlmModel": vlmModel,
            "vlmPrompt": vlmPrompt
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Config.configFileURL)
        }
    }
}
