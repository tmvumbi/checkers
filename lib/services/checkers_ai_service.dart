import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import '../engine/ai/ai_config.dart';
import '../engine/ai/checkers_ai.dart';
import '../engine/checkers_engine.dart';
import '../engine/move.dart';

/// Runs the AI search off the UI isolate (PRD §7.3).
abstract class AiService {
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level);
}

/// One long-lived AI isolate: the transposition table and move-ordering
/// history stay warm across moves, which buys real depth on the same
/// budget. Every request resyncs the full position (config + move list),
/// so undos and game switches need no special handling; the isolate
/// resets its tables when the rules change.
class PersistentIsolateAiService implements AiService {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<SendPort>? _handshake;
  final Map<int, Completer<String>> _pending = {};
  int _requestId = 0;

  Future<SendPort> _ensureStarted() async {
    final ready = _sendPort;
    if (ready != null) {
      return ready;
    }
    if (_handshake != null) {
      return _handshake!.future;
    }
    final handshake = _handshake = Completer<SendPort>();
    final receivePort = _receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        handshake.complete(message);
        return;
      }
      final map = (message as Map).cast<String, dynamic>();
      _pending.remove(map['id'] as int)?.complete(map['move'] as String);
    });
    _isolate = await Isolate.spawn(
      _aiIsolateMain,
      receivePort.sendPort,
      debugName: 'checkers-ai',
    );
    return handshake.future;
  }

  @override
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level) async {
    final sendPort = await _ensureStarted();
    final id = ++_requestId;
    final completer = Completer<String>();
    _pending[id] = completer;
    sendPort.send({
      'id': id,
      'engine': jsonEncode(engine.toJson()),
      'level': level.name,
    });
    final moveJson = await completer.future;
    return Move.fromJson(jsonDecode(moveJson) as Map<String, dynamic>);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _handshake = null;
    for (final completer in _pending.values) {
      completer.completeError(StateError('AI service disposed'));
    }
    _pending.clear();
  }
}

void _aiIsolateMain(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  CheckersAi? ai;
  String? lastRulesJson;
  var gameSeed = 0;

  port.listen((message) {
    final map = (message as Map).cast<String, dynamic>();
    final engine = CheckersEngine.fromJson(
      jsonDecode(map['engine'] as String) as Map<String, dynamic>,
    );
    final rulesJson = jsonEncode(engine.config.toJson());

    // A fresh game gets a fresh variety seed so openings differ between
    // games while staying deterministic within one.
    if (engine.moveHistory.length < 2 || rulesJson != lastRulesJson) {
      gameSeed = Random().nextInt(1 << 30) + 1;
    }

    final level = AiLevel.values.byName(map['level'] as String);
    final config = AiConfig.forLevel(level).withVarietySeed(gameSeed);

    if (ai == null) {
      ai = CheckersAi(engine, config);
    } else {
      if (rulesJson != lastRulesJson) {
        // Same-size variants share Zobrist keys but not legality/eval:
        // never reuse table entries across rule sets.
        ai!.resetTables();
      }
      ai!
        ..engine = engine
        ..config = config;
    }
    lastRulesJson = rulesJson;

    final choice = ai!.chooseMove();
    mainPort.send({'id': map['id'], 'move': jsonEncode(choice.move.toJson())});
  });
}

/// Cold single-shot variant (previous behavior), kept as a fallback.
class IsolateAiService implements AiService {
  @override
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level) async {
    final engineJson = jsonEncode(engine.toJson());
    final levelName = level.name;
    final moveJson = await Isolate.run(() {
      final rebuilt = CheckersEngine.fromJson(
        jsonDecode(engineJson) as Map<String, dynamic>,
      );
      final ai = CheckersAi(
        rebuilt,
        AiConfig.forLevel(AiLevel.values.byName(levelName)),
      );
      return jsonEncode(ai.chooseMove().move.toJson());
    });
    return Move.fromJson(jsonDecode(moveJson) as Map<String, dynamic>);
  }
}

/// Synchronous variant for tests.
class SyncAiService implements AiService {
  @override
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level) async {
    final rebuilt = CheckersEngine.fromJson(engine.toJson());
    final ai = CheckersAi(rebuilt, AiConfig.forLevel(level));
    return ai.chooseMove().move;
  }
}
