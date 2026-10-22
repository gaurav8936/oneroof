# SwiftUI: a closure from another hosting view reads a stale copy of a view's @State / @StateObject

**Found:** 2026-10-21 (LAB-523) · **Where:** `UI/NewSessionSheet.swift` + `UI/IssuePickerPanel.swift`

**Symptom:** the sheet showed 3 issues picked while the picker panel (its own `NSPanel` + `NSHostingController`) showed none; ticks in the panel did not reliably reach the sheet.

**Cause:** the panel got closures like `picked: { pickedIssues }` and `toggle: { toggleIssue($0) }` that captured a copy of the sheet struct. Reading or writing the sheet's `@State` through that copy outside its body is not the live storage (and a `@StateObject` read from a copy can even be a new instance).

**Rule:** state shared by two hosting views goes in one `ObservableObject` (`IssueSelection`), handed to the second view as the object itself (`let sel = selection` inside a body action), never via closures into the first view. The owning view reacts with `.onReceive(obj.$value.dropFirst()) { _ in DispatchQueue.main.async { … } }`.
