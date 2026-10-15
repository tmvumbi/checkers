import 'dart:async';

import 'package:dartvex/dartvex.dart';

import '../../core/network/api_error.dart';
import '../../core/network/api_result.dart';

/// Fetches a Firebase ID token for Convex (`forceRefresh` after expiry).
typedef ConvexTokenFetcher =
    Future<String?> Function({required bool forceRefresh});

/// The slice of the Convex client the app's services use. One real
/// implementation over dartvex; tests substitute fakes.
abstract class ConvexGateway {
  Future<dynamic> query(String name, [Map<String, dynamic> args = const {}]);
  Future<dynamic> mutation(String name, [Map<String, dynamic> args = const {}]);
  Future<dynamic> action(String name, [Map<String, dynamic> args = const {}]);

  /// Live query results; errors surface as stream errors.
  Stream<dynamic> watch(String name, [Map<String, dynamic> args = const {}]);

  /// Sends [fetchToken]'s tokens with every request (null clears auth).
  Future<void> setAuth(ConvexTokenFetcher? fetchToken);
}

class DartvexGateway implements ConvexGateway {
  DartvexGateway(this.client);

  final ConvexClient client;
  AuthHandle? _authHandle;

  @override
  Future<dynamic> query(String name, [Map<String, dynamic> args = const {}]) =>
      client.query(name, args);

  @override
  Future<dynamic> mutation(
    String name, [
    Map<String, dynamic> args = const {},
  ]) => client.mutate(name, args);

  @override
  Future<dynamic> action(String name, [Map<String, dynamic> args = const {}]) =>
      client.action(name, args);

  @override
  Stream<dynamic> watch(String name, [Map<String, dynamic> args = const {}]) {
    late final ConvexSubscription subscription;
    late final StreamController<dynamic> controller;
    StreamSubscription<QueryResult>? listener;
    controller = StreamController<dynamic>(
      onListen: () {
        subscription = client.subscribe(name, args);
        listener = subscription.stream.listen((result) {
          switch (result) {
            case QuerySuccess(:final value):
              controller.add(value);
            case QueryError(:final message, :final data):
              controller.addError(ConvexException(message, data: data));
            case QueryLoading():
              break;
          }
        }, onError: controller.addError);
      },
      onCancel: () async {
        await listener?.cancel();
        subscription.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setAuth(ConvexTokenFetcher? fetchToken) async {
    await _authHandle?.cancel();
    _authHandle = null;
    if (fetchToken == null) {
      await client.clearAuth();
      return;
    }
    _authHandle = await client.setAuthWithRefresh(fetchToken: fetchToken);
  }
}

/// The application error code a Convex function threw (`ConvexError`
/// data), matching the codes the Postgres RPCs raised.
String convexErrorCode(Object error) {
  if (error is ConvexException) {
    final data = error.data;
    if (data is String && data.isNotEmpty) return data;
    if (data is Map && data['code'] is String) return data['code'] as String;
    return error.message;
  }
  return 'unknown';
}

/// Runs [action], mapping Convex failures to [ApiError]s.
Future<ApiResult<T>> guardConvex<T>(Future<T> Function() action) async {
  try {
    return Success(await action());
  } on ConvexException catch (error) {
    return Failure(
      ApiError(code: convexErrorCode(error), message: error.message),
    );
  } catch (error) {
    return Failure(ApiError(code: 'unknown', message: error.toString()));
  }
}

Map<String, dynamic> asRow(Object? value) =>
    (value as Map).cast<String, dynamic>();

List<Map<String, dynamic>> asRows(Object? value) => [
  for (final row in (value as List? ?? const [])) asRow(row),
];
