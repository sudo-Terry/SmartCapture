import AppKit

// 백그라운드(메뉴 막대) 에이전트로 실행한다.
// .accessory 정책: Dock 아이콘 없이 메뉴 막대에만 존재한다.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
