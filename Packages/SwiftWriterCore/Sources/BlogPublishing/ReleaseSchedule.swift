import Foundation

/// The standing cadence a blog goes out on - Tuesdays and Thursdays at 08:00, say.
///
/// Pure arithmetic over a calendar, with no idea that WordPress exists. Allocating the
/// next free slot is the one piece of the publishing workflow worth being certain about,
/// because getting it wrong means two posts landing in the same hour, so it is kept here
/// where it can be tested without a network.
public struct ReleaseSchedule: Sendable, Equatable {
    /// `Calendar` weekday numbers, where Sunday is 1. Tuesday is 3 and Thursday is 5.
    public var weekdays: Set<Int>
    public var hour: Int
    public var minute: Int
    /// Slots are local wall-clock times: 08:00 stays 08:00 when the clocks change, which
    /// is what a reader sees and what "8am on a Tuesday" means.
    public var timeZone: TimeZone

    public init(weekdays: Set<Int>, hour: Int, minute: Int = 0, timeZone: TimeZone = .current) {
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
        self.timeZone = timeZone
    }

    /// The cadence briansmith.photos already runs on.
    public static func tuesdaysAndThursdays(
        at hour: Int = 8,
        timeZone: TimeZone = .current
    ) -> ReleaseSchedule {
        ReleaseSchedule(weekdays: [3, 5], hour: hour, timeZone: timeZone)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Every slot strictly after `date`, in order.
    ///
    /// `count` bounds the walk so a schedule with no matching weekday cannot spin forever.
    public func slots(after date: Date, count: Int) -> [Date] {
        guard count > 0, !weekdays.isEmpty else { return [] }
        let calendar = self.calendar
        var found: [Date] = []
        // One component set per weekday, since DateComponents holds a single weekday and
        // enumerateDates matches one pattern at a time. Merging the streams keeps them in
        // order without assuming which weekday comes first in the week.
        var streams: [(iterator: AnyIterator<Date>, next: Date?)] = weekdays.sorted().map { weekday in
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0
            var cursor = date
            let iterator = AnyIterator<Date> {
                guard let slot = calendar.nextDate(
                    after: cursor, matching: components,
                    matchingPolicy: .nextTime, direction: .forward
                ) else { return nil }
                cursor = slot
                return slot
            }
            return (iterator, iterator.next())
        }
        while found.count < count {
            guard let pick = streams.indices
                .filter({ streams[$0].next != nil })
                .min(by: { streams[$0].next! < streams[$1].next! })
            else { break }
            found.append(streams[pick].next!)
            streams[pick].next = streams[pick].iterator.next()
        }
        return found
    }

    /// The first slot after `date` that nothing already occupies.
    public func nextFreeSlot(after date: Date, taken: Set<Date> = []) -> Date? {
        allocate(1, after: date, taken: taken).first
    }

    /// `count` free slots in order, none colliding with `taken` or with each other.
    ///
    /// Searching a bounded window rather than looping until satisfied means a caller that
    /// asks for more slots than the window holds gets fewer, not a hang.
    public func allocate(_ count: Int, after date: Date, taken: Set<Date> = []) -> [Date] {
        guard count > 0 else { return [] }
        let occupied = Set(taken.map { $0.timeIntervalSinceReferenceDate.rounded() })
        var allocated: [Date] = []
        for slot in slots(after: date, count: (count + taken.count) * 2 + 8) {
            guard !occupied.contains(slot.timeIntervalSinceReferenceDate.rounded()) else { continue }
            allocated.append(slot)
            if allocated.count == count { break }
        }
        return allocated
    }
}
