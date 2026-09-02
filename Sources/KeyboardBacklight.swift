import Foundation

/// Controls the built-in keyboard backlight through CoreBrightness.
///
/// `KeyboardBrightnessClient` is private, so everything here goes through
/// `NSClassFromString` and hand-cast `objc_msgSend`. The selectors were read off the
/// class at runtime on macOS 27 / Apple Silicon; if a future macOS renames them,
/// `init?` fails and the app degrades to doing nothing rather than crashing.
final class KeyboardBacklight {

    private typealias IdFn = @convention(c) (AnyObject, Selector) -> AnyObject?
    private typealias FloatForKbFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias BoolForKbFn = @convention(c) (AnyObject, Selector, UInt64) -> ObjCBool
    private typealias SetBrightnessFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool
    private typealias SetAutoFn = @convention(c) (AnyObject, Selector, ObjCBool, UInt64) -> ObjCBool

    private let client: AnyObject
    private let keyboardID: UInt64

    private let msgId: IdFn
    private let msgFloat: FloatForKbFn
    private let msgBool: BoolForKbFn
    private let msgSet: SetBrightnessFn
    private let msgSetAuto: SetAutoFn

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              let send = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend") else { return nil }

        let client = cls.init()
        let msgId = unsafeBitCast(send, to: IdFn.self)
        let msgBool = unsafeBitCast(send, to: BoolForKbFn.self)

        // Prefer the built-in keyboard; an external one has its own backlight we shouldn't touch.
        let ids = (msgId(client, NSSelectorFromString("copyKeyboardBacklightIDs")) as? [NSNumber]) ?? []
        let builtIn = ids.first { msgBool(client, NSSelectorFromString("isKeyboardBuiltIn:"), $0.uint64Value).boolValue }
        guard let chosen = builtIn ?? ids.first else { return nil }

        self.client = client
        self.keyboardID = chosen.uint64Value
        self.msgId = msgId
        self.msgBool = msgBool
        self.msgFloat = unsafeBitCast(send, to: FloatForKbFn.self)
        self.msgSet = unsafeBitCast(send, to: SetBrightnessFn.self)
        self.msgSetAuto = unsafeBitCast(send, to: SetAutoFn.self)
    }

    /// Current backlight level, 0...1.
    var brightness: Double {
        Double(msgFloat(client, NSSelectorFromString("brightnessForKeyboard:"), keyboardID))
    }

    /// Sets the backlight level, 0...1. Returns false when CoreBrightness rejects it.
    @discardableResult
    func setBrightness(_ value: Double) -> Bool {
        let clamped = Float(min(max(value, 0), 1))
        return msgSet(client, NSSelectorFromString("setBrightness:forKeyboard:"), clamped, keyboardID).boolValue
    }

    /// Whether macOS is running its own ambient auto-brightness on this keyboard.
    var systemAutoBrightnessEnabled: Bool {
        msgBool(client, NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:"), keyboardID).boolValue
    }

    /// Turns macOS's own auto-brightness off, so it doesn't fight us over the same keyboard.
    @discardableResult
    func setSystemAutoBrightness(_ enabled: Bool) -> Bool {
        msgSetAuto(client, NSSelectorFromString("enableAutoBrightness:forKeyboard:"),
                   ObjCBool(enabled), keyboardID).boolValue
    }

    /// True while macOS is idle-dimming the backlight (you walked away).
    var isDimmed: Bool {
        msgBool(client, NSSelectorFromString("isBacklightDimmedOnKeyboard:"), keyboardID).boolValue
    }

    /// True while the system is holding the backlight off (display asleep, and similar).
    var isSuppressed: Bool {
        msgBool(client, NSSelectorFromString("isBacklightSuppressedOnKeyboard:"), keyboardID).boolValue
    }

    /// False on a keyboard with no ambient hardware behind it.
    var hasAmbientFeature: Bool {
        msgBool(client, NSSelectorFromString("isAmbientFeatureAvailableOnKeyboard:"), keyboardID).boolValue
    }
}
