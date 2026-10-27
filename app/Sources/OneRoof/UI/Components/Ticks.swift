import Combine
import Foundation

/// Clocks for views (LAB-1329). A `Timer.publish(…).autoconnect()` made in a view's init or body is a new timer each
/// time the parent redraws: while the model changed faster than the interval, it never fired (the editor's 2 s save
/// flush among them). These are made once, run on the main run loop, and are shared by every view that listens.
enum Ticks {
    static let second = clock(1)
    static let twoSeconds = clock(2)
    static let threeSeconds = clock(3)
    static let tenSeconds = clock(10)

    private static func clock(_ every: TimeInterval) -> AnyPublisher<Date, Never> {
        Timer.publish(every: every, tolerance: every * 0.1, on: .main, in: .common).autoconnect().share().eraseToAnyPublisher()
    }
}
