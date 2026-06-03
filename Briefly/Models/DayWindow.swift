import Foundation

struct DayWindow: Equatable {
    let start: Date
    let end: Date
    let calendar: Calendar

    static func current(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DayWindow {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DayWindow(start: start, end: end, calendar: calendar)
    }

    static func trailing(
        hours: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DayWindow {
        let end = now
        let start = calendar.date(byAdding: .hour, value: -hours, to: end) ?? end.addingTimeInterval(TimeInterval(-hours * 60 * 60))
        return DayWindow(start: start, end: end, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    func isSameDay(as other: DayWindow) -> Bool {
        calendar.isDate(start, inSameDayAs: other.start)
    }
}
