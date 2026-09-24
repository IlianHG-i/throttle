import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 0) {
            SystemGaugesView()
                .padding()
                .background(.regularMaterial)

            Divider()

            if monitor.apps.isEmpty {
                Spacer()
                Text("Chargement des applications…")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(monitor.apps) { app in
                    AppRowView(app: app)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 480, height: 600)
    }
}

private struct SystemGaugesView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RAM Brider")
                    .font(.headline)
                Spacer()
                if monitor.suspendedCount > 0 {
                    Button {
                        monitor.resumeAll()
                    } label: {
                        Label("Reprendre tout (\(monitor.suspendedCount))", systemImage: "arrow.clockwise")
                    }
                    .help("Reprend toutes les applications actuellement en pause")
                }
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quitter RAM Brider")
            }

            gauge(
                title: "Memoire",
                fraction: monitor.usedMemoryFraction,
                detail: "\(Formatting.bytes(monitor.usedMemoryBytes)) / \(Formatting.bytes(monitor.totalMemoryBytes))"
            )

            gauge(
                title: "CPU",
                fraction: monitor.systemCPUPercent / 100,
                detail: Formatting.percent(monitor.systemCPUPercent)
            )
            Text("Inclut les processus systeme (WindowServer, kernel_task...) non listes ci-dessous")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func gauge(title: String, fraction: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(color(for: fraction))
        }
    }

    private func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SystemMonitor())
}
