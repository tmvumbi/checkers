import 'dart:async';

import 'package:checkers/core/network/api_error.dart';
import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/services/account_deletion_service.dart';
import 'package:checkers/services/profile_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient {}

class _Auth extends Mock implements GoTrueClient {}

class _Photos extends Mock implements ProfilePhotoService {}

class _Rpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _Rpc(this.action);
  final Future<dynamic> Function() action;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return action().then(onValue, onError: onError);
  }
}

void main() {
  late _Client client;
  late _Auth auth;
  late _Photos photos;
  late SupabaseAccountDeletionService service;

  setUp(() {
    client = _Client();
    auth = _Auth();
    photos = _Photos();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(
      User(
        id: 'test-user',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-09-15T00:00:00Z',
      ),
    );
    service = SupabaseAccountDeletionService(
      client: client,
      photoService: photos,
    );
  });

  test('waits for successful avatar removal before deleting account', () async {
    final cleanup = Completer<ApiResult<void>>();
    when(
      () => photos.deleteAvatar('test-user'),
    ).thenAnswer((_) => cleanup.future);
    when(
      () => client.rpc<dynamic>('delete_account'),
    ).thenAnswer((_) => _Rpc(() async => null));

    final deletion = service.deleteCurrentAccount();
    verifyNever(() => client.rpc<dynamic>('delete_account'));
    cleanup.complete(const Success(null));
    expect(await deletion, isA<Success<void>>());
    verify(() => client.rpc<dynamic>('delete_account')).called(1);
  });

  test('storage failure preserves account and allows a later retry', () async {
    const error = ApiError(
      code: 'delete-failed',
      message: 'Storage unavailable',
    );
    when(
      () => photos.deleteAvatar('test-user'),
    ).thenAnswer((_) async => const Failure(error));
    final failure = await service.deleteCurrentAccount();
    expect(failure, isA<Failure<void>>());
    expect((failure as Failure<void>).error, same(error));
    verifyNever(() => client.rpc<dynamic>('delete_account'));

    when(
      () => photos.deleteAvatar('test-user'),
    ).thenAnswer((_) async => const Success(null));
    when(
      () => client.rpc<dynamic>('delete_account'),
    ).thenAnswer((_) => _Rpc(() async => null));
    expect(await service.deleteCurrentAccount(), isA<Success<void>>());
  });

  test('RPC failure can be retried after the avatar is already gone', () async {
    when(
      () => photos.deleteAvatar('test-user'),
    ).thenAnswer((_) async => const Success(null));
    when(() => client.rpc<dynamic>('delete_account')).thenAnswer(
      (_) => _Rpc(
        () async =>
            throw const PostgrestException(message: 'Unavailable', code: '503'),
      ),
    );
    final result = await service.deleteCurrentAccount();
    expect((result as Failure<void>).error.code, '503');

    when(
      () => client.rpc<dynamic>('delete_account'),
    ).thenAnswer((_) => _Rpc(() async => null));
    expect(await service.deleteCurrentAccount(), isA<Success<void>>());
    verify(() => photos.deleteAvatar('test-user')).called(2);
  });

  test(
    'missing session never removes files or calls the deletion RPC',
    () async {
      when(() => auth.currentUser).thenReturn(null);
      final result = await service.deleteCurrentAccount();
      expect((result as Failure<void>).error.code, 'not-authenticated');
      verifyNever(() => photos.deleteAvatar(any()));
      verifyNever(() => client.rpc<dynamic>('delete_account'));
    },
  );
}
