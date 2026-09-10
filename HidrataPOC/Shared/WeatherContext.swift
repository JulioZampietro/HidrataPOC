/// Compiled into both targets — `IntakeLog`'s initializer takes an optional
/// `WeatherContext`, and `IntakeLog` itself is shared with the `HydrationWidget`
/// extension (see `IntakeLogService`). The extension never produces one of these
/// itself (no WeatherKit/location access there); it just needs the type to compile.
struct WeatherContext {
    let temperaturaC: Double
    let umidadeRelativa: Double
    let sensacaoTermicaC: Double
}
