import 'package:supabase_flutter/supabase_flutter.dart';

/// Player feedback inbox (emailed to the team and listed in the admin
/// console).
abstract class FeedbackService {
  /// Submits [text] as the signed-in player [uid]. Throws on failure.
  Future<void> submit({required String uid, required String text});
}

class SupabaseFeedbackService implements FeedbackService {
  SupabaseFeedbackService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  @override
  Future<void> submit({required String uid, required String text}) async {
    await client.from('feedback').insert({'uid': uid, 'text': text});
  }
}
