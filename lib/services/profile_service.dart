import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import '../data/models/user_profile.dart';

abstract class ProfileService {
  Future<ApiResult<UserProfile?>> getProfile(String uid);
  Future<ApiResult<UserProfile>> upsertProfile(UserProfile profile);
}

class SupabaseProfileService implements ProfileService {
  SupabaseProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<ApiResult<UserProfile?>> getProfile(String uid) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      return Success(row == null ? null : UserProfile.fromJson(row));
    } on PostgrestException catch (error) {
      return Failure(
        ApiError(
          code: error.code ?? 'profile-load-failed',
          message: error.message,
        ),
      );
    } catch (error) {
      return Failure(ApiError(code: 'unknown', message: error.toString()));
    }
  }

  @override
  Future<ApiResult<UserProfile>> upsertProfile(UserProfile profile) async {
    try {
      final row = await _client
          .from('profiles')
          .upsert(profile.toUpsertJson())
          .select()
          .single();
      return Success(UserProfile.fromJson(row));
    } on PostgrestException catch (error) {
      return Failure(
        ApiError(
          code: error.code ?? 'profile-save-failed',
          message: error.message,
        ),
      );
    } catch (error) {
      return Failure(ApiError(code: 'unknown', message: error.toString()));
    }
  }
}
