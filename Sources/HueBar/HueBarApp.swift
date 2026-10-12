import SwiftUI

@main
struct HueBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HueStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(store)
        } label: {
            Image(nsImage: StatusIcon.image(connected: store.isConnected, lightsOn: store.anyLightOn))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon: a light bulb while connected (filled when any light is on), unplugged otherwise.
@MainActor
enum StatusIcon {
    private static let disconnected = PhosphorIcon.plugs.templateImage(.bold)
    private static let allOff = PhosphorIcon.lightbulb.templateImage(.bold)
    private static let someOn = PhosphorIcon.lightbulb.templateImage(.fill)

    static func image(connected: Bool, lightsOn: Bool) -> NSImage {
        guard connected else { return disconnected }
        return lightsOn ? someOn : allOff
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Stay out of the Dock even when run without the bundle's LSUIElement (e.g. via `swift run`).
        NSApp.setActivationPolicy(.accessory)
    }
}
