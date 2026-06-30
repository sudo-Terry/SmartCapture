import AppKit
import Carbon.HIToolbox

/// Carbon `RegisterEventHotKey` 기반 전역 단축키 관리자.
/// (Carbon 핫키는 손쉽게 시스템 전역 단축키를 잡으며 손쉽게 접근성 권한도 필요 없다.)
final class HotKeyManager {
    typealias Handler = () -> Void

    private var handlers: [UInt32: Handler] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    // 자주 쓰는 modifier 묶음 (⌃⌥⌘)
    static let controlOptionCommand: UInt32 =
        UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)

    init() {
        installHandler()
    }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                NSLog("[SmartCapture] 단축키 눌림 감지 (id=\(hkID.id))")
                manager.handlers[hkID.id]?()
                return noErr
            },
            1, &spec, selfPtr, &eventHandler
        )
    }

    /// 전역 단축키 등록. keyCode 는 Carbon 가상 키코드(kVK_ANSI_3 등).
    func register(keyCode: Int, modifiers: UInt32, handler: @escaping Handler) {
        let id = nextID
        nextID += 1
        handlers[id] = handler

        let signature: OSType = 0x4D535348 // 'MSSH'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            refs.append(ref)
            NSLog("[SmartCapture] 단축키 등록 성공 (code=\(keyCode), id=\(id))")
        } else {
            NSLog("[SmartCapture] 단축키 등록 실패 (code=\(keyCode), status=\(status))")
        }
    }

    deinit {
        for ref in refs where ref != nil {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
