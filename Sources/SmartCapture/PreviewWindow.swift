import AppKit

/// macOS 기본 스크린샷 앱처럼, 캡처 직후 우측 하단에 잠깐 떠 있는
/// 작은 썸네일 팝업. 클릭하면 Quick Look 미리보기로 크게 볼 수 있다.
final class PreviewController: NSObject {
    private var window: NSWindow?
    private var dismissTimer: Timer?
    private let displaySeconds: TimeInterval

    init(displaySeconds: TimeInterval) {
        self.displaySeconds = displaySeconds
    }

    func show(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        dismissExisting(animated: false)

        let thumb = makeThumbnailWindow(image: image, url: url)
        window = thumb
        thumb.alphaValue = 0
        thumb.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            thumb.animator().alphaValue = 1
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: displaySeconds, repeats: false
        ) { [weak self] _ in
            self?.dismissExisting(animated: true)
        }
    }

    private func makeThumbnailWindow(image: NSImage, url: URL) -> NSWindow {
        // 썸네일 크기 (가로 기준 240pt, 비율 유지)
        let maxWidth: CGFloat = 240
        let ratio = image.size.height / max(image.size.width, 1)
        let w = maxWidth
        let h = min(maxWidth * ratio, 180)
        let padding: CGFloat = 8
        let frameSize = NSSize(width: w + padding * 2, height: h + padding * 2)

        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screen.maxX - frameSize.width - 20,
            y: screen.minY + 20
        )

        let win = ClickableWindow(
            contentRect: NSRect(origin: origin, size: frameSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.hasShadow = true
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 둥근 카드 배경
        let container = NSView(frame: NSRect(origin: .zero, size: frameSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.masksToBounds = true

        let imageView = NSImageView(frame: NSRect(x: padding, y: padding, width: w, height: h))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        container.addSubview(imageView)

        win.contentView = container
        win.onClick = { [weak self] in
            self?.openPreview(url)
        }
        return win
    }

    /// 클릭 시: 썸네일을 닫고 Quick Look 패널로 크게 보여준다.
    private func openPreview(_ url: URL) {
        dismissExisting(animated: false)
        // qlmanage -p 는 책임/응답자 체인 없이도 진짜 Quick Look 패널을 띄운다.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(url)   // 실패 시 Preview.app 으로 대체
        }
    }

    private func dismissExisting(animated: Bool) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let win = window else { return }
        window = nil
        guard animated else { win.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }
}

/// 클릭을 받아 콜백을 호출하는 보더리스 윈도.
private final class ClickableWindow: NSWindow {
    var onClick: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
