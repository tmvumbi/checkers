/// Supabase project configuration.
///
/// The anon key is a publishable key: it grants nothing beyond what row-level
/// security allows and ships inside the app binary by design.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://checkers-api.contribution.club',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJzdXBhYmFzZSIsImlhdCI6MTc4NjY0OTc2MCwiZXhwIjo0OTQyMzIzMzYwLCJyb2xlIjoiYW5vbiJ9.OfzvkiZV4M7nnAoLY3Ig1gqoH5SyeStXQ_dSNsXwxDg',
  );
}
