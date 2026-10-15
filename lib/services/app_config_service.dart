import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the public remote config (`app_config` row `public`): version gate,
/// AdMob settings, clocks, points rules. Readable before sign-in.
abstract class AppConfigService {
  /// The config object, or an empty map when none is published.
  Future<Map<String, dynamic>> fetchPublicConfig();
}

class SupabaseAppConfigService implements AppConfigService {
  SupabaseAppConfigService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  @override
  Future<Map<String, dynamic>> fetchPublicConfig() async {
    final row = await client
        .from('app_config')
        .select('config')
        .eq('id', 'public')
        .maybeSingle();
    return (row?['config'] as Map?)?.cast<String, dynamic>() ?? const {};
  }
}
