import SwiftUI

@main
struct FireflyApp: App {
    @StateObject private var controller = FireflyController()

    var body: some Scene {
        MenuBarExtra {
            FireflyView(controller: controller)
        } label: {
            Image(systemName: symbol)
        }
        .menuBarExtraStyle(.window)
    }

    /// The menu bar glyph doubles as the status readout: filled when it's driving the
    /// backlight, hollow when it has stood down.
    private var symbol: String {
        guard controller.settings.enabled else { return "keyboard" }
        if controller.overriddenUntil != nil { return "keyboard.badge.ellipsis" }
        return controller.applied > 0.02 ? "keyboard.fill" : "keyboard"
    }
}
