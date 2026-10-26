import SwiftUI
import OneRoofCore

/// Full dock (step 0): seats, roofd, machine, needs you, tonight.
struct StatusDock: View {
    var dock: V2Dock; var tokens: V2Planes
    var body: some View {
        HStack(spacing: 16) {
            ForEach(dock.seats) { s in
                HStack(spacing: 7) {
                    Text(s.name).font(.system(size: 9.5, weight: .bold)).foregroundStyle(s.badgeText)
                        .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(s.badge))
                    Text(s.label).font(.system(size: 10.5)).foregroundStyle(tokens.text2).lineLimit(1)
                }.opacity(s.off ? 0.45 : 1)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Color(.systemGreen)).frame(width: 6, height: 6)
                Text(dock.roofd).foregroundStyle(tokens.text2)
                if dock.foundationsIssues > 0 { Text("· \(dock.foundationsIssues) foundations issue").foregroundStyle(Color(.systemRed)) }
            }.font(.system(size: 11)).lineLimit(1)
            Text(dock.machine).font(.system(size: 11)).foregroundStyle(tokens.text2).lineLimit(1)
            Pill(text: "Needs you · \(dock.needsYou)", tokens: tokens)
            Pill(text: "Tonight · \(dock.tonight)", tokens: tokens)
        }
        .padding(.horizontal, 16).frame(height: 50).background(tokens.rail)
        .overlay(alignment: .top) { Rectangle().fill(tokens.separatorStrong).frame(height: 1) }
    }
}

/// One-line dock at the foot of the session column (step 1).
struct DockLine: View {
    var dock: V2Dock; var tokens: V2Planes
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(.systemGreen)).frame(width: 6, height: 6)
            Text("roofd ·")
            Text(dock.seats.filter { !$0.off }.map { "\($0.name) \(Int($0.used * 100))%" }.joined(separator: " · "))
            Spacer()
            Text("⌃⌘J")
        }
        .font(.system(size: 10)).foregroundStyle(tokens.text2).lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(tokens.separator).frame(height: 1) }
    }
}

struct Pill: View {
    var text: String; var tokens: V2Planes
    var body: some View { Text(text).font(.system(size: 11)).padding(.horizontal, 11).padding(.vertical, 4).background(Capsule().fill(tokens.surface)) }
}
