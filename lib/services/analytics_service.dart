import 'package:firebase_analytics/firebase_analytics.dart';

/// Analytics abstraction, backed by Firebase Analytics (kopo parity).
/// The no-op stays for tests and for platforms where Firebase failed to
/// initialize.
abstract class AnalyticsService {
  Future<void> logEvent(String name, [Map<String, Object?>? parameters]);
}

class NoopAnalyticsService implements AnalyticsService {
  @override
  Future<void> logEvent(String name, [Map<String, Object?>? parameters]) {
    return Future<void>.value();
  }
}

class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService({FirebaseAnalytics? analytics})
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logEvent(String name, [Map<String, Object?>? parameters]) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: parameters == null
            ? null
            : <String, Object>{
                for (final entry in parameters.entries)
                  if (entry.value != null) entry.key: entry.value!,
              },
      );
    } catch (_) {
      // Analytics must never break the app.
    }
  }
}
