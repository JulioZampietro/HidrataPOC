import Foundation

/// `PolicyContextProvider` backed by the same helpers `NotificationScheduler.captureContext`
/// uses to fill `NotificationEvent` (WeatherContextService, CalendarContextService,
/// HydrationMath, UserProfile), so every feature means what it meant in the training data.
///
/// Values are "as known at decision time": weather is the current reading and only
/// applied to slots later today (another day's weather is unknown, so it's left out
/// and the encoder imputes it — same rule the scheduler uses for persona variants);
/// deficit and last intake count the logs recorded so far.
@MainActor
final class AppPolicyContextProvider: PolicyContextProvider {
    private let profile: UserProfile
    private let logs: [IntakeLog]
    private let calendar: Calendar
    private let fetchWeather: @MainActor () async -> WeatherContext?
    private var fetchedWeather: WeatherContext??

    init(profile: UserProfile, logs: [IntakeLog], calendar: Calendar = .current,
         fetchWeather: @escaping @MainActor () async -> WeatherContext?) {
        self.profile = profile
        self.logs = logs
        self.calendar = calendar
        self.fetchWeather = fetchWeather
    }

    /// Fetched once, on first use, and shared by every slot (and by the scheduler's
    /// persona-variant pick), so nothing is fetched when there's nothing to decide.
    func currentWeather() async -> WeatherContext? {
        if let fetchedWeather { return fetchedWeather }
        let weather = await fetchWeather()
        fetchedWeather = .some(weather)
        return weather
    }

    func context(forSlotAt slotDate: Date, now: Date) async -> SlotContext {
        let dayWeather = calendar.isDate(slotDate, inSameDayAs: now) ? await currentWeather() : nil
        let calendarContext = CalendarContextService.shared.currentContext(around: slotDate)
        let consumed = HydrationMath.totalML(logs, on: slotDate, calendar: calendar)
        let deficit = HydrationMath.deficitML(metaDiariaML: profile.metaDiariaML, consumidoHojeML: consumed)
        return SlotContext(
            temperaturaC: dayWeather?.temperaturaC,
            umidadeRelativa: dayWeather?.umidadeRelativa,
            sensacaoTermicaC: dayWeather?.sensacaoTermicaC,
            ocupadoNoMomento: calendarContext?.ocupadoNoMomento,
            densidadeEventosDia: calendarContext?.densidadeEventosDia,
            deficitAcumuladoML: Double(deficit),
            metaDiariaML: Double(profile.metaDiariaML),
            lastIntake: logs.map(\.timestamp).filter { $0 <= now }.max(),
            idade: profile.idade,
            generoRaw: profile.genero
        )
    }
}
