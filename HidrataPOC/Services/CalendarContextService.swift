import EventKit
import Foundation

struct CalendarContext {
    let ocupadoNoMomento: Bool
    let densidadeEventosDia: Int
}

/// Reads only busy/free status and same-day event count via EventKit — never event
/// title, location, or attendees (explicitly out of scope for this POC).
@MainActor
final class CalendarContextService {
    static let shared = CalendarContextService()

    private let store = EKEventStore()

    private init() {}

    func requestAccessIfNeeded() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
    }

    /// Returns nil on any failure/denied-access — calendar context is enrichment, not
    /// something that should block a notification from going out.
    func currentContext(around moment: Date) -> CalendarContext? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .minute, value: -15, to: moment) ?? moment
        let windowEnd = calendar.date(byAdding: .minute, value: 15, to: moment) ?? moment
        let ocupadoPredicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let ocupado = !store.events(matching: ocupadoPredicate).isEmpty

        let dayStart = calendar.startOfDay(for: moment)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? moment
        let dayPredicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let densidade = store.events(matching: dayPredicate).count

        return CalendarContext(ocupadoNoMomento: ocupado, densidadeEventosDia: densidade)
    }
}
