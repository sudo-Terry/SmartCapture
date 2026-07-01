import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var config = Config.load()
    private var vlmMenu: NSMenu!                 // 동적으로 갱신되는 VLM 서브메뉴
    private var permissionWarned = false         // 권한 경고 1회만

    private lazy var screenshotService = ScreenshotService(config: config)
    private lazy var cleanupService = CleanupService(config: config)
    private let hotKeys = HotKeyManager()
    private lazy var preview = PreviewController(displaySeconds: config.previewSeconds)
    private lazy var searchIndex = SearchIndex(directory: Config.appSupportDir)
    private lazy var searchController = SearchController(index: searchIndex)
    private var vlmService: VLMService?
    private var folderWatcher: FolderWatcher?

    private func makeVLMService() -> VLMService? {
        guard config.vlmEnabled else { return nil }
        let service = VLMService(
            endpoint: config.vlmEndpoint,
            model: config.vlmModel,
            prompt: config.vlmPrompt)
        service.onCaption = { [weak self] caption, url in
            self?.searchIndex.updateCaption(path: url.path, caption: caption)
            FileMarker.writeCaption(caption, to: url)
            NSLog("[SmartCapture] VLM 캡션: \(caption)")
        }
        return service
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        vlmService = makeVLMService()
        setupStatusItem()
        setupCaptureCallback()
        registerHotKeys()
        // 휴지통으로 옮긴 캡처는 검색 인덱스에서도 제거한다.
        cleanupService.onRemoved = { [weak self] path in
            self?.searchIndex.remove(path: path)
        }
        cleanupService.start()

        // 시작 시 한 번, 그리고 저장 폴더 변화를 감지할 때마다 없는 파일을 인덱스에서 정리한다.
        // (사용자가 Finder 등에서 캡처를 직접 지운 경우 대응)
        searchIndex.pruneMissing()
        folderWatcher = FolderWatcher(url: config.saveDirectory) { [weak self] in
            self?.searchIndex.pruneMissing()
        }
        folderWatcher?.start()
    }

    // MARK: - 메뉴 막대

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "SmartCapture")
        }

        let menu = NSMenu()
        menu.addItem(makeItem("전체 화면 캡처  (⌃⌥⌘3)", #selector(captureFull)))
        menu.addItem(makeItem("영역 캡처  (⌃⌥⌘4)", #selector(captureRegion)))
        menu.addItem(makeItem("창 캡처  (⌃⌥⌘5)", #selector(captureWindow)))
        menu.addItem(.separator())
        menu.addItem(makeItem("스크린샷 검색…  (⌃⌥⌘F)", #selector(showSearch)))

        // 이미지 맥락 해석(VLM) 서브메뉴 — 열릴 때마다 동적 갱신
        let vlmItem = NSMenuItem(title: "이미지 맥락 해석 (VLM)", action: nil, keyEquivalent: "")
        vlmMenu = NSMenu(title: "VLM")
        vlmMenu.delegate = self
        vlmItem.submenu = vlmMenu
        menu.addItem(vlmItem)

        menu.addItem(.separator())
        menu.addItem(makeItem("저장 폴더 열기", #selector(openFolder)))
        menu.addItem(makeItem("지금 오래된 파일 정리", #selector(cleanupNow)))
        menu.addItem(makeItem("설정 파일 열기", #selector(openConfig)))
        menu.addItem(.separator())
        menu.addItem(makeItem("종료", #selector(quit)))
        statusItem.menu = menu
    }

    // MARK: - VLM 서브메뉴 (NSMenuDelegate)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === vlmMenu else { return }
        menu.removeAllItems()

        // 1) 켜기/끄기 토글 (기본: OCR만)
        let toggle = makeItem("로컬 LLM으로 맥락 해석 사용", #selector(toggleVLM))
        toggle.state = config.vlmEnabled ? .on : .off
        menu.addItem(toggle)

        let hint = NSMenuItem(
            title: config.vlmEnabled ? "현재: OCR + 맥락 캡션" : "현재: OCR 텍스트만 (기본)",
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        // 2) 모델 선택 — 설치된 Ollama 모델을 조회
        let models = VLMService.installedModels(endpoint: config.vlmEndpoint)
        if models == nil {
            let status = NSMenuItem(title: "⚠︎ Ollama 서버에 연결 안 됨", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(makeItem("Ollama 설치하기…", #selector(openOllamaSite)))
            menu.addItem(makeItem("모델 받는 법…", #selector(showVLMSetupHint)))
        } else if models!.isEmpty {
            let none = NSMenuItem(title: "설치된 모델 없음", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            menu.addItem(makeItem("비전 모델 받는 법…", #selector(showVLMSetupHint)))
        } else {
            let header = NSMenuItem(title: "모델 선택", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for name in models! {
                let item = makeItem(name, #selector(selectModel(_:)))
                item.representedObject = name
                item.state = (name == config.vlmModel) ? .on : .off
                menu.addItem(item)
            }
        }
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 캡처 후처리 (클립보드 복사는 서비스가 처리, 여기선 미리보기)

    private func setupCaptureCallback() {
        screenshotService.onCaptured = { [weak self] url in
            self?.preview.show(url)        // 하단 썸네일 미리보기
            self?.analyzeAndIndex(url)     // 백그라운드에서 의미 분석 + 색인
        }
        // 캡처가 권한 문제로 실패하면(파일이 안 생기면) 한 번 안내한다.
        screenshotService.onPermissionError = { [weak self] message in
            self?.showPermissionAlert(message)
        }
    }

    private func showPermissionAlert(_ message: String) {
        guard !permissionWarned else { return }
        permissionWarned = true
        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = """
        캡처가 저장되지 않았습니다. 시스템 설정 > 개인정보 보호 및 보안 > 화면 기록 에서
        SmartCapture 을 허용한 뒤 앱을 다시 실행하세요.

        (참고: \(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        """
        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    /// 캡처 직후 Vision 분석을 백그라운드에서 수행하고 검색 인덱스에 저장한다.
    /// (캡처/미리보기 흐름을 막지 않도록 별도 큐에서 실행)
    private func analyzeAndIndex(_ url: URL) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let analysis = ImageAnalyzer.analyze(url)

            // 정보가 파일을 따라가도록 OCR/태그를 파일에 함께 기록.
            FileMarker.writeOCR(analysis.ocrText, to: url)
            if !analysis.tags.isEmpty {
                // Finder/Spotlight 에서도 검색되도록 상위 태그를 Finder 태그로 단다.
                try? (url as NSURL).setResourceValue(
                    Array(analysis.tags.prefix(3)), forKey: .tagNamesKey)
            }

            self?.searchIndex.index(
                path: url.path,
                capturedAt: Date(),
                ocr: analysis.ocrText,
                tags: analysis.tags,
                embedding: analysis.embedding)

            // VLM 이 켜져 있으면 맥락 캡션을 추가로 생성(느리므로 별도 큐에서 나중에 채움).
            self?.vlmService?.enqueue(url)
        }
    }

    // MARK: - 전역 단축키

    private func registerHotKeys() {
        let mods = HotKeyManager.controlOptionCommand
        hotKeys.register(keyCode: kVK_ANSI_3, modifiers: mods) { [weak self] in
            self?.screenshotService.capture(.fullScreen)
        }
        hotKeys.register(keyCode: kVK_ANSI_4, modifiers: mods) { [weak self] in
            self?.screenshotService.capture(.region)
        }
        hotKeys.register(keyCode: kVK_ANSI_5, modifiers: mods) { [weak self] in
            self?.screenshotService.capture(.window)
        }
        hotKeys.register(keyCode: kVK_ANSI_F, modifiers: mods) { [weak self] in
            self?.searchController.toggle()
        }
    }

    // MARK: - 메뉴 액션

    @objc private func captureFull()   { screenshotService.capture(.fullScreen) }
    @objc private func captureRegion() { screenshotService.capture(.region) }
    @objc private func captureWindow() { screenshotService.capture(.window) }

    @objc private func showSearch() {
        searchController.present()
    }

    // MARK: - VLM 메뉴 액션

    @objc private func toggleVLM() {
        config.vlmEnabled.toggle()
        config.save()
        vlmService = makeVLMService()   // 즉시 반영(재실행 불필요)

        // 켰는데 Ollama 가 없으면 설치 안내.
        if config.vlmEnabled, VLMService.installedModels(endpoint: config.vlmEndpoint) == nil {
            let alert = NSAlert()
            alert.messageText = "Ollama 가 필요합니다"
            alert.informativeText = """
            로컬 LLM 맥락 해석을 쓰려면 Ollama 설치 후 비전 모델을 받아야 합니다.
            설치: https://ollama.com/download
            모델: 프로젝트 폴더에서 ./setup_vlm.sh 실행

            설치 전까지는 OCR 텍스트만으로 색인/검색됩니다.
            """
            alert.addButton(withTitle: "Ollama 페이지 열기")
            alert.addButton(withTitle: "나중에")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
            }
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        config.vlmModel = name
        config.save()
        vlmService = makeVLMService()
    }

    @objc private func openOllamaSite() {
        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
    }

    @objc private func showVLMSetupHint() {
        let alert = NSAlert()
        alert.messageText = "비전 모델 받기"
        alert.informativeText = """
        터미널에서 프로젝트 폴더의 setup 스크립트를 실행하면 모델을 받고 자동으로 켭니다.

            ./setup_vlm.sh            # llava:7b (품질)
            ./setup_vlm.sh moondream  # 더 가볍고 빠름

        또는 직접:  ollama pull llava:7b
        """
        alert.runModal()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(config.saveDirectory)
    }

    @objc private func cleanupNow() {
        let count = cleanupService.cleanupNow()
        let alert = NSAlert()
        alert.messageText = "정리 완료"
        alert.informativeText = count > 0
            ? "오래된 캡처 \(count)개를 휴지통으로 옮겼습니다."
            : "옮길 만큼 오래된 캡처가 없습니다."
        alert.runModal()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.configFileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
