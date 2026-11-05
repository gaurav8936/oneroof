import SwiftUI
import OneRoofCore

/// LAB-2242 · E8.1 Lessons (screen lane B owns this file). A sheet over any tab: `nav.openLesson(id)` (every number's
/// Lesson ›), Esc closes. Content: lessons.json (EvalsLearnStore.book) + Try it; 2.0.3's How to walkthrough lives here
/// too (`nav.lessonsPart = .howTo`) until it merges into Overview + "Your first test".
/// Placeholder: today's Learn tab and How to tab until rebuilt.
struct EvalsLessonsSheet: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let model: AppModel
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Lessons").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Segmented(options: EvalsNav.LessonsPart.allCases.map { ($0, $0.rawValue) }, selection: $nav.lessonsPart)
                Spacer()
                RoofButton("Close") { nav.sheet = nil }.help("Close (Esc)")
            }
            switch nav.lessonsPart {
            case .lessons: EvalsLearnV2(board: board, nav: nav)
            case .howTo: EvalsHowToTab(nav: nav, model: model)
            }
        }
        .padding(20)
        .frame(minWidth: 980, idealWidth: 1180, minHeight: 620, idealHeight: 820, alignment: .topLeading)
    }
}
