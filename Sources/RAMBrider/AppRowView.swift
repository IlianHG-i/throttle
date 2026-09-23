import SwiftUI

struct AppRowView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    let app: AppInfo

    private var isProtected: Bool {
        ProtectedApps.isProtected(app.runningApplication)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                    .foregroundStyle(app.isSuspended ? .secondary : .primary)
                Text("PID \(app.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                monitor.terminate(app)
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(isProtected)
            .help(isProtected ? "Application protegee" : "Quitter l'application")

            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatting.bytes(app.memoryBytes))
                    .font(.callout.monospacedDigit())
                Text(Formatting.appCPUPercent(app.cpuPercent) + " CPU")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)

            Button {
                monitor.toggleSuspend(app)
                monitor.refresh()
            } label: {
                Image(systemName: app.isSuspended ? "play.fill" : "pause.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .disabled(isProtected)
            .help(isProtected ? "Application protegee" : (app.isSuspended ? "Reprendre" : "Mettre en pause"))
        }
        .padding(.vertical, 4)
        .opacity(app.isSuspended ? 0.6 : 1.0)
    }
}
