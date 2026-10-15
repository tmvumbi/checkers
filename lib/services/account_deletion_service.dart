import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import 'profile_photo_service.dart';

abstract class AccountDeletionService {
  Future<ApiResult<void>> deleteCurrentAccount();
}

class SupabaseAccountDeletionService implements AccountDeletionService {
  SupabaseAccountDeletionService({
    SupabaseClient? client,
    ProfilePhotoService? photoService,
  }) : _client = client ?? Supabase.instance.client,
       _photoService =
           photoService ?? SupabaseProfilePhotoService(client: client);

  final SupabaseClient _client;
  final ProfilePhotoService _photoService;

  @override
  Future<ApiResult<void>> deleteCurrentAccount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return const Failure(
        ApiError(
          code: 'not-authenticated',
          message: 'Sign in before deleting your account.',
        ),
      );
    }

    try {
      // Storage.remove handles missing files too, so this also works for
      // guests and retries after the file was removed but the RPC failed.
      // Keep the session/account intact when storage cleanup fails.
      final cleanup = await _photoService.deleteAvatar(uid);
      if (cleanup is Failure<void>) {
        return cleanup;
      }
      await _client.rpc<dynamic>('delete_account');
      return const Success(null);
    } on PostgrestException catch (error) {
      return Failure(
        ApiError(
          code: error.code ?? 'account-delete-failed',
          message: error.message,
        ),
      );
    } catch (error) {
      return Failure(
        ApiError(code: 'account-delete-failed', message: error.toString()),
      );
    }
  }
}
