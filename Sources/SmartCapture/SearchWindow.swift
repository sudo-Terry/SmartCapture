import AppKit
import ImageIO

/// 단축키로 띄우는 검색창. 입력에 따라 인덱스를 실시간 검색하고,
/// 결과(썸네일 + 파일명 + OCR 일부)를 보여준다. 더블클릭하면 Quick Look.
final class SearchController: NSObject, NSSearchFieldDelegate,
                             NSTableViewDataSource, NSTableViewDelegate {

    private let index: SearchIndex
    private var window: SearchPanel?
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var results: [SearchIndex.Result] = []

    init(index: SearchIndex) {
        self.index = index
    }

    /// 단축키 토글: 보이면 숨기고, 아니면 띄운다.
    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            present()
        }
    }

    func present() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        searchField.becomeFirstResponder()
        runSearch()
    }

    // MARK: - UI 구성

    private func buildWindow() {
        let rect = NSRect(x: 0, y: 0, width: 580, height: 500)
        let panel = SearchPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "스크린샷 검색"
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak panel] in panel?.orderOut(nil) }

        let content = NSView(frame: rect)

        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "내용(OCR)·태그로 검색…"
        content.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 68
        tableView.headerView = nil
        tableView.style = .inset
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)
        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.menu = makeContextMenu()
        scroll.documentView = tableView
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        panel.contentView = content
        window = panel
    }

    // MARK: - 검색

    func controlTextDidChange(_ obj: Notification) {
        runSearch()
    }

    private func runSearch() {
        let query = searchField.stringValue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = self.index.search(query)
            DispatchQueue.main.async {
                self.results = found
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - 테이블

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: ResultCell.id, owner: self) as? ResultCell)
            ?? ResultCell()
        cell.configure(with: results[row])
        return cell
    }

    // MARK: - 우클릭 컨텍스트 메뉴

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let ql = NSMenuItem(title: "Quick Look 미리보기", action: #selector(quickLookRow), keyEquivalent: "")
        let reveal = NSMenuItem(title: "Finder에서 파일 위치 열기", action: #selector(revealRow), keyEquivalent: "")
        let copy = NSMenuItem(title: "파일 경로 복사", action: #selector(copyPathRow), keyEquivalent: "")
        for item in [ql, reveal, copy] { item.target = self; menu.addItem(item) }
        return menu
    }

    /// 우클릭한 행(clickedRow) 우선, 없으면 선택된 행의 URL.
    private func targetURL() -> URL? {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < results.count else { return nil }
        return URL(fileURLWithPath: results[row].path)
    }

    @objc private func openSelected() { quickLook(targetURL()) }
    @objc private func quickLookRow() { quickLook(targetURL()) }

    @objc private func revealRow() {
        guard let url = targetURL() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])   // Finder 에서 파일 선택해 표시
    }

    @objc private func copyPathRow() {
        guard let url = targetURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func quickLook(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep(); return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSWorkspace.shared.open(url) }
    }
}

/// Esc 로 닫히는 검색 패널.
final class SearchPanel: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - 결과 셀

private final class ResultCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("ResultCell")

    private let thumb = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")
    private var currentPath: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = ResultCell.id
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 4
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleLabel, snippetLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(thumb)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 84),
            thumb.heightAnchor.constraint(equalToConstant: 56),

            textStack.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with result: SearchIndex.Result) {
        currentPath = result.path
        let url = URL(fileURLWithPath: result.path)
        titleLabel.stringValue = url.lastPathComponent

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let date = formatter.string(from: result.capturedAt)

        // 사람이 읽기 좋은 순서: VLM 캡션 > OCR 텍스트.
        let body = (result.caption.isEmpty ? result.ocr : result.caption)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tagPart = result.tags.isEmpty ? "" : "  ·  \(result.tags)"
        snippetLabel.stringValue = body.isEmpty
            ? "\(date)\(tagPart)"
            : "\(date)\(tagPart)\n\(body)"

        thumb.image = nil
        loadThumbnail(url)
    }

    /// 큰 PNG도 빠르게 로드하도록 ImageIO 로 축소 썸네일을 만든다.
    private func loadThumbnail(_ url: URL) {
        let pathAtRequest = currentPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 168,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
            else { return }
            let image = NSImage(cgImage: cg, size: .zero)
            DispatchQueue.main.async {
                guard let self, self.currentPath == pathAtRequest else { return }
                self.thumb.image = image
            }
        }
    }
}
