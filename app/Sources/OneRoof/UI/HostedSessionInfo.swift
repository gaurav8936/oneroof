import SwiftUI
import OneRoofCore

struct HostedSessionInfo: View {
    let launch: HostedPreparedLaunch
    @State private var usage: HostedSessionUsage?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text("\(launch.provider.displayName) · \(launch.model)").font(.caption).textSelection(.enabled)
                if let usage {
                    Text(String(format: "%d requests · $%.4f reserved / $%.2f session ceiling", usage.requests, usage.reservedUSD, usage.ceilingUSD)).font(.caption)
                    if let tokens = usage.reportedTokens { Text("\(tokens) provider-reported tokens").font(.caption) }
                }
                Text("Reservations are conservative estimates. Approve tools in the native terminal. Reopening a live session keeps its conversation; relaunch starts a new conversation with the same remaining budget.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task(id: context.date) { usage = await Task.detached(priority: .utility) { HostedSessionUsage.read(launch) }.value }
        }
    }
}
