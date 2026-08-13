/// Analytics abstraction. Kopo used Firebase Analytics; for checkers a
/// concrete backend is deferred (PRD §8) — the no-op keeps call sites in
/// place so a provider can be dropped in later.
abstract class AnalyticsService {
  Future<void> logEvent(String name, [Map<String, Object?>? parameters]);
}

class NoopAnalyticsService implements AnalyticsService {
  @override
  Future<void> logEvent(String name, [Map<String, Object?>? parameters]) {
    return Future<void>.value();
  }
}
