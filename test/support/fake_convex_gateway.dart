import 'dart:async';

import 'package:checkers/services/convex/convex_gateway.dart';

typedef ConvexHandler = FutureOr<dynamic> Function(Map<String, dynamic> args);

/// In-memory [ConvexGateway]: answers calls from per-function handlers and
/// records every call, so services can be tested without a backend.
class FakeConvexGateway implements ConvexGateway {
  final Map<String, ConvexHandler> handlers = {};
  final Map<String, StreamController<dynamic>> streams = {};
  final List<(String, Map<String, dynamic>)> calls = [];
  ConvexTokenFetcher? tokenFetcher;
  int setAuthCalls = 0;

  void on(String name, ConvexHandler handler) => handlers[name] = handler;

  Iterable<Map<String, dynamic>> callsTo(String name) =>
      calls.where((c) => c.$1 == name).map((c) => c.$2);

  Future<dynamic> _run(String name, Map<String, dynamic> args) async {
    calls.add((name, args));
    final handler = handlers[name];
    if (handler == null) {
      throw StateError('no fake handler for $name');
    }
    return handler(args);
  }

  @override
  Future<dynamic> query(String name, [Map<String, dynamic> args = const {}]) =>
      _run(name, args);

  @override
  Future<dynamic> mutation(
    String name, [
    Map<String, dynamic> args = const {},
  ]) => _run(name, args);

  @override
  Future<dynamic> action(String name, [Map<String, dynamic> args = const {}]) =>
      _run(name, args);

  @override
  Stream<dynamic> watch(String name, [Map<String, dynamic> args = const {}]) {
    calls.add((name, args));
    return (streams[name] ??= StreamController<dynamic>.broadcast()).stream;
  }

  @override
  Future<void> setAuth(ConvexTokenFetcher? fetchToken) async {
    setAuthCalls++;
    tokenFetcher = fetchToken;
  }
}
