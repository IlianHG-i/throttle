import SwiftUI

@main
struct RAMBriderApp: App {
    @ObservedObject private var monitor = SystemMonitor.shared

    init() {
        SystemMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(Formatting.percent(monitor.usedMemoryFraction * 100))
        }
        .menuBarExtraStyle(.window)
    }
}
