import SwiftUI
import OneRoofCore

/// LAB-2242 · E8 Lessons (screen lane B): a sheet over any tab — `nav.openLesson(id)` from every number's Lesson ›, Esc
/// closes. Three parts: Lessons (16 in six groups with ✓ / ● / ○, each with its text, example, Try it with real examples
/// "in your tests", Where this shows up and Next; Your first test, free), How to (2.0.3's eight-scene walkthrough, kept
/// so nothing is lost) and Where everything went (the coverage map: every 2.0.3 feature → its 2.0.4 home, the same rows
/// as docs/evals-v2-coverage.md, from OneRoofCore EvalsCoverage).
struct EvalsLessonsSheet: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let model: AppModel
    @Environment(\.theme) private var t
    @AppStorage(EvalsLearnStore.doneKey, store: Prefs.viewState) private var doneRaw = ""
    @State private var showMap = false

    enum Part: String, CaseIterable { case lessons = "Lessons", howTo = "How to", map = "Where everything went" }

    private var part: Binding<Part> {
        Binding(get: { showMap ? .map : nav.lessonsPart == .howTo ? .howTo : .lessons },
                set: { p in
                    showMap = p == .map
                    if p != .map { nav.lessonsPart = p == .howTo ? .howTo : .lessons }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text("Lessons").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                        if EvalsDraft.isDraft { EvalsDraftTag() }
                    }
                    Text(subtitle).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Segmented(options: Part.allCases.map { ($0, $0.rawValue) }, selection: part).fixedSize()
                RoofButton("Close") { nav.sheet = nil }.help("Close (Esc)")
            }
            switch part.wrappedValue {
            case .lessons: EvalsLearnV2(board: board, nav: nav)
            case .howTo: EvalsHowToTab(nav: nav, model: model)
            case .map: EvalsCoverageMap(nav: nav)
            }
        }
        .padding(20)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 620, idealHeight: 820, alignment: .topLeading)
        .onChange(of: nav.lesson) { _, _ in showMap = false }
    }

    private var subtitle: String {
        let n = EvalsLearnStore.book?.lessons.count ?? 16
        let done = Set(doneRaw.split(separator: ",").map(String.init)).intersection(Set(EvalsLearnStore.book?.lessons.map(\.id) ?? [])).count
        return "\(n) lessons · \(done) done · every number in Evals links here: hover any number for what it means, then Lesson ›"
    }
}

/// Where everything went: every 2.0.3 Evals feature, its 2.0.4 home and Kept / Merged / Moved / Removed / New. A row
/// with a screen opens it.
struct EvalsCoverageMap: View {
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var filter: EvalsCoverageRow.Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Nothing from 2.0.3 was lost: each feature and where it lives now. The same list is in the repo as docs/evals-v2-coverage.md.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Spacer()
                FieldMenu(title: filter?.rawValue ?? "All \(EvalsCoverage.rows.count)", height: 24, expand: false) {
                    Button("All \(EvalsCoverage.rows.count)") { filter = nil }
                    ForEach(EvalsCoverageRow.Status.allCases, id: \.self) { s in
                        Button("\(s.rawValue) · \(EvalsCoverage.rows.filter { $0.status == s }.count)") { filter = s }
                    }
                }
                .fixedSize()
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow { ForEach(["2.0.3 feature", "Was in", "Now in 2.0.4", "Status"], id: \.self) { EvalsLabel($0) } }.padding(.vertical, 8)
                    ForEach(EvalsCoverage.rows.filter { filter == nil || $0.status == filter }) { r in
                        GridRow {
                            Text(r.feature).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            Text(r.was).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                            Button { open(r) } label: {
                                Text(r.home + (r.screen == nil ? "" : " ›")).ui(TypeScale.small).foregroundStyle(r.screen == nil ? t.text.color : t.accentText.color)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.plain).disabled(r.screen == nil)
                            Text(r.status.rawValue).ui(TypeScale.caption, .semibold)
                                .foregroundStyle(r.status == .removed ? t.needsText.color : r.status == .added ? t.accentText.color : t.diffAddText.color)
                        }
                        .padding(.vertical, 6)
                        GridRow { Rectangle().fill(t.separator.color).frame(height: 1).gridCellColumns(4) }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func open(_ r: EvalsCoverageRow) {
        guard let s = r.screen else { return }
        switch s {
        case .overview, .compare, .changes, .realHistory, .ourTasks, .benchmarks: if let tb = s.tab { nav.go(tb) }
        case .oneTest: nav.route = .oneTest(run: nil, sample: nil, only: nil, other: nil)
        case .allResults: nav.route = .allResults
        case .oneTask: nav.openTask(nil)
        case .grader: nav.openGrader(nil)
        case .oneBenchmark: nav.openBenchmark(nav.benchmark ?? "gsm8k")
        case .setup: nav.test(nil)
        case .lessons: nav.openLesson(nav.lesson ?? "first-eval")
        }
    }
}
