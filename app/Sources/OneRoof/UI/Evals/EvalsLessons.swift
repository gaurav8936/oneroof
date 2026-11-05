import SwiftUI
import OneRoofCore

/// LAB-2242 · E8 Lessons (screen lane B): a sheet over any tab — `nav.openLesson(id)` from every number's Lesson ›, Esc
/// closes. Three parts: Lessons (18 in six groups since 2.0.5, + "One-shot jobs and agent jobs" and "Loop runs as evidence"; with ✓ / ● / ○, each with its text, example, Try it with real examples
/// "in your tests", Where this shows up and Next; Your first test, free), How to (2.0.3's eight-scene walkthrough, kept
/// so nothing is lost) and Where everything went (the coverage map: every 2.0.4 element → its 2.0.5 home and every 2.0.3
/// feature → its 2.0.4 home, the same rows as docs/evals-v3-coverage.md, from OneRoofCore EvalsCoverage).
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
            case .map: EvalsCoverageMap(nav: nav, toLessons: { showMap = false; nav.lessonsPart = .lessons })
            }
        }
        .padding(20)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 620, idealHeight: 820, alignment: .topLeading)
        .onChange(of: nav.lesson) { _, _ in showMap = false }
    }

    private var subtitle: String {
        let n = EvalsLearnStore.book?.lessons.count ?? 18
        let done = Set(doneRaw.split(separator: ",").map(String.init)).intersection(Set(EvalsLearnStore.book?.lessons.map(\.id) ?? [])).count
        return "\(n) lessons · \(done) done · every number in Evals links here: hover any number for what it means, then Lesson ›"
    }
}

/// Where everything went: every 2.0.4 Evals element and its 2.0.5 home (and, one switch away, every 2.0.3 feature and its
/// 2.0.4 home), with Kept / Merged / Moved / Removed / New. A row with a screen opens it with a visible button (LAB-2255).
/// The same rows as docs/evals-v3-coverage.md (LAB-2261).
struct EvalsCoverageMap: View {
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var filter: EvalsCoverageRow.Status?
    @State private var release: EvalsCoverageRow.Release = .v3
    /// A row whose home is Lessons switches this sheet to its Lessons part.
    var toLessons: () -> Void = {}

    private var inRelease: [EvalsCoverageRow] { EvalsCoverage.rows.filter { $0.release == release } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(release == .v3
                     ? "Nothing from 2.0.4 was lost: each element and where it lives now. The same list is in the repo as docs/evals-v3-coverage.md."
                     : "Nothing from 2.0.3 was lost in 2.0.4: each feature and its 2.0.4 home; Open goes to where it lives in 2.0.5.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Segmented(options: EvalsCoverageRow.Release.allCases.map { ($0, $0.rawValue) }, selection: $release).fixedSize()
                FieldMenu(title: filter.map { f in "\(f.rawValue) · \(inRelease.filter { $0.status == f }.count)" } ?? "All \(inRelease.count)", height: 24, expand: false) {
                    Button("All \(inRelease.count)") { filter = nil }
                    ForEach(EvalsCoverageRow.Status.allCases, id: \.self) { s in
                        Button("\(s.rawValue) · \(inRelease.filter { $0.status == s }.count)") { filter = s }
                    }
                }
                .fixedSize()
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        ForEach([release.featureTitle, "Was in", release.homeTitle, "Status", ""], id: \.self) { EvalsLabel($0) }
                    }
                    .padding(.vertical, 8)
                    ForEach(inRelease.filter { filter == nil || $0.status == filter }) { r in
                        GridRow {
                            Text(r.feature).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            Text(r.was).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                            Text(r.home).ui(TypeScale.small).foregroundStyle(t.text.color)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Text(r.status.rawValue).ui(TypeScale.caption, .semibold)
                                .foregroundStyle(r.status == .removed ? t.needsText.color : r.status == .added ? t.accentText.color : t.diffAddText.color)
                            if let s = r.v3 {
                                RoofButton("Open ›") { open(s) }.help("Open \(s.title)")
                            } else {
                                Color.clear.frame(width: 1, height: 1)
                            }
                        }
                        .padding(.vertical, 6)
                        GridRow { Rectangle().fill(t.separator.color).frame(height: 1).gridCellColumns(5) }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .onChange(of: release) { _, _ in filter = nil }
    }

    /// Every row opens its 2.0.5 home (a page, a drill-down or a sheet) through the v3 navigation.
    private func open(_ s: EvalsV3Screen) {
        if s == .lessons { toLessons(); return }
        nav.open(s)
    }
}
