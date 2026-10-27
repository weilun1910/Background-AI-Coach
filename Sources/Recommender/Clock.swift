import Foundation

/// The app's idea of "now". Real use leaves it alone. The persona demo moves
/// it to the moment being played, so "starts in 15 min" and "one card a day"
/// work on a pretend day.
enum Clock {
    static var offset: TimeInterval = 0

    static var now: Date { Date().addingTimeInterval(offset) }

    static func set(_ date: Date) { offset = date.timeIntervalSinceNow }

    static func reset() { offset = 0 }
}
