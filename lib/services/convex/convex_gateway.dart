import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  DartvexGateway(
    this.client, {
    required String deploymentUrl,
    Duration queryTimeout = const Duration(seconds: 15),
    HttpClient? httpClient,
  }) : _queryEndpoint = Uri.parse(
         '${deploymentUrl.replaceAll(RegExp(r'/+$'), '')}/api/query',
       ),
       _queryTimeout = queryTimeout,
       _http = httpClient ?? HttpClient();

  final ConvexClient client;
  final Uri _queryEndpoint;
  final Duration _queryTimeout;
  final HttpClient _http;
  AuthHandle? _authHandle;
  ConvexTokenFetcher? _fetchToken;

  /// One-shot reads go through Convex's HTTP query API rather than
  /// `ConvexClient.query`: dartvex answers a re-subscribed query from its
  /// local result cache, so a second read of the same query+args returned
  /// the value from the first read even after the data changed. Live data
  /// still uses [watch] (WebSocket subscriptions).
  @override
  Future<dynamic> query(String name, [Map<String, dynamic> args = const {}]) {
    return _httpQuery(name, args).timeout(_queryTimeout);
  }

  Future<dynamic> _httpQuery(String name, Map<String, dynamic> args) async {
    final token = await _fetchToken?.call(forceRefresh: false);
    final request = await _http.postUrl(_queryEndpoint);
    request.headers.contentType = ContentType.json;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.add(
      utf8.encode(jsonEncode({'path': name, 'args': args, 'format': 'json'})),
    );
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ConvexException('HTTP ${response.statusCode}: $body');
    }
    if (decoded is Map && decoded['status'] == 'success') {
      return decoded['value'];
    }
    if (decoded is Map && decoded['status'] == 'error') {
      throw ConvexException(
        (decoded['errorMessage'] as String?) ?? 'query failed',
        data: decoded['errorData'],
      );
    }
    throw ConvexException('HTTP ${response.statusCode}: $body');
  }

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
    _fetchToken = fetchToken;
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
