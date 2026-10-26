import SwiftUI
import OneRoofCore

/// New session (A10.1).
struct NewSessionSheetV2: View {
    struct SeatChoice: Identifiable { var id: String { name }; var name: String; var room: String; var available: Bool }
    var seats: [SeatChoice]; var repos: [String]; var tickets: [String]
    var onLaunch: (_ seat: String, _ repo: String, _ ticket: String?, _ doneWhen: String, _ message: String, _ when: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var seat = ""; @State private var repo = ""; @State private var ticket = ""; @State private var doneWhen = ""; @State private var message = ""; @State private var when = "Now"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New session").font(.system(size: 18, weight: .bold))
            Form {
                LabeledContent("Agent and seat") { HStack { ForEach(seats) { s in Toggle(isOn: Binding(get: { seat == s.name }, set: { if $0 { seat = s.name } })) { Text(s.name).bold() + Text(" " + s.room).foregroundColor(.secondary) }.toggleStyle(.button).disabled(!s.available) } } }
                Picker("Repo", selection: $repo) { ForEach(repos, id: \.self) { Text($0) } }
                Picker("Ticket", selection: $ticket) { Text("None").tag(""); ForEach(tickets, id: \.self) { Text($0) } }
                TextField("Done when", text: $doneWhen, axis: .vertical)
                TextField("Opening message", text: $message, axis: .vertical).lineLimit(3...6)
                Picker("Start", selection: $when) { ForEach(["Now", "Next", "Tonight", "Planned"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            }
            Label("Starts in ~/Projects · one memory · READ-FIRST will load", systemImage: "checkmark.circle").foregroundStyle(Color(.systemGreen)).font(.system(size: 11))
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Launch") { onLaunch(seat, repo, ticket.isEmpty ? nil : ticket, doneWhen, message, when); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(KeymapV2.launchSelected.swiftUI) }
        }
        .padding(20).frame(width: 560)
        .onAppear { seat = seats.first(where: \.available)?.name ?? ""; repo = repos.first ?? "" }
    }
}

/// ⌘K / How do I… (A10.2). Ranking comes from LearnMatch plus session/file/ticket search.
struct SearchPalette: View {
    struct Result: Identifiable { var id = UUID(); var section: String; var symbol: String; var title: String; var detail: String; var key: String }
    @Binding var query: String; var results: [Result]; var onOpen: (Result) -> Void; var onSend: (Result) -> Void
    var body: some View {
        VStack(spacing: 0) {
            TextField("Search, or ask how do I…", text: $query).textFieldStyle(.plain).font(.system(size: 16)).padding(14)
            Divider()
            List {
                ForEach(Dictionary(grouping: results, by: \.section).sorted { $0.key < $1.key }, id: \.key) { sec, rs in
                    Section(sec) { ForEach(rs) { r in HStack { Image(systemName: r.symbol).frame(width: 16); Text(r.title).bold(); Text(r.detail).foregroundStyle(.secondary); Spacer(); Text(r.key).foregroundStyle(.tertiary) }.onTapGesture { onOpen(r) } } }
                }
            }.listStyle(.plain).frame(height: 320)
            Divider()
            Text("↩ open · ⌘↩ send to a session · sessions, files, docs, tickets and Learn").font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
        }.frame(width: 640)
    }
}

/// Settings › Appearance (A10.3).
struct LooksPicker: View {
    @Binding var look: Look
    var onCustomize: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .lastTextBaseline) { VStack(alignment: .leading) { Text("Appearance").font(.system(size: 20, weight: .bold)); Text("One look sets every panel at once").foregroundStyle(.secondary) }; Spacer(); Button("Customize each panel…", action: onCustomize).buttonStyle(.link) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(Look.allCases) { l in
                    let p = V2Planes(look: l)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) { p.rail.frame(width: 44); p.window.overlay(RoundedRectangle(cornerRadius: 6).fill(p.terminal).padding(8)); p.surface.frame(width: 44) }
                            .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(l == look ? Color.accentColor : .gray.opacity(0.2), lineWidth: l == look ? 3 : 1))
                        Text(l.title).bold(); Text(l.blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.onTapGesture { look = l }
                }
            }
        }.padding(24).frame(width: 900)
    }
}
