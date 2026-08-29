import Foundation
import Testing
@testable import BlogPublishing

/// Fixed points, so the tests do not drift with the wall clock. The blog's own zone.
private let pacific = TimeZone(identifier: "America/Los_Angeles")!

private func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = pacific
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: string)!
}

private func describe(_ slot: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = pacific
    formatter.dateFormat = "yyyy-MM-dd HH:mm EEE"
    return formatter.string(from: slot)
}

@Suite("Release schedule")
struct ReleaseScheduleTests {
    let schedule = ReleaseSchedule.tuesdaysAndThursdays(timeZone: pacific)

    @Test("Slots land on Tuesdays and Thursdays at 08:00, in order")
    func cadence() {
        // A Friday, so the next slot has to skip the weekend.
        let slots = schedule.slots(after: date("2026-08-28 12:00"), count: 5)
        #expect(slots.map(describe) == [
            "2026-09-01 08:00 Tue",
            "2026-09-03 08:00 Thu",
            "2026-09-08 08:00 Tue",
            "2026-09-10 08:00 Thu",
            "2026-09-15 08:00 Tue",
        ])
    }

    @Test("A slot earlier the same day is still ahead of the caller")
    func sameDay() {
        // 06:00 on a Tuesday: today's 08:00 has not happened yet, so it counts.
        #expect(describe(schedule.slots(after: date("2026-09-01 06:00"), count: 1)[0])
                == "2026-09-01 08:00 Tue")
        // 09:00 the same day: it has, so the next one is Thursday.
        #expect(describe(schedule.slots(after: date("2026-09-01 09:00"), count: 1)[0])
                == "2026-09-03 08:00 Thu")
    }

    @Test("Slots already spoken for are skipped")
    func skipsTaken() {
        let taken: Set<Date> = [date("2026-09-01 08:00"), date("2026-09-03 08:00")]
        let next = schedule.nextFreeSlot(after: date("2026-08-28 12:00"), taken: taken)
        #expect(next.map(describe) == "2026-09-08 08:00 Tue")
    }

    @Test("Allocating several never hands out the same slot twice")
    func allocatesDistinct() {
        let taken: Set<Date> = [date("2026-09-03 08:00")]
        let slots = schedule.allocate(3, after: date("2026-08-28 12:00"), taken: taken)
        #expect(slots.map(describe) == [
            "2026-09-01 08:00 Tue",
            "2026-09-08 08:00 Tue",
            "2026-09-10 08:00 Thu",
        ])
        #expect(Set(slots).count == slots.count)
    }

    @Test("08:00 stays 08:00 across the end of daylight saving")
    func survivesTheClockChange() {
        // Pacific falls back on 2026-11-01. A slot is a wall-clock time, not a fixed
        // offset, so the reader still sees 8am and the UTC offset is what moves.
        let slots = schedule.slots(after: date("2026-10-27 09:00"), count: 3)
        #expect(slots.map(describe) == [
            "2026-10-29 08:00 Thu",
            "2026-11-03 08:00 Tue",
            "2026-11-05 08:00 Thu",
        ])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "HH:mm"
        #expect(formatter.string(from: slots[0]) == "15:00")
        #expect(formatter.string(from: slots[1]) == "16:00")
    }

    @Test("A schedule with no weekdays yields nothing rather than looping")
    func emptyScheduleTerminates() {
        let empty = ReleaseSchedule(weekdays: [], hour: 8, timeZone: pacific)
        #expect(empty.slots(after: date("2026-08-28 12:00"), count: 5).isEmpty)
        #expect(empty.nextFreeSlot(after: date("2026-08-28 12:00")) == nil)
    }
}
