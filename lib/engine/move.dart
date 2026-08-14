/// A fully-disambiguated move: origin, landing path, and captured squares.
///
/// [path] holds every intermediate landing square plus the final square, in
/// order — a quiet move has a single entry. [captured] is aligned with the
/// jump order for multi-captures.
class Move {
  Move({
    required this.from,
    required List<int> path,
    List<int> captured = const [],
    this.promotes = false,
  }) : path = List.unmodifiable(path),
       captured = List.unmodifiable(captured);

  final int from;
  final List<int> path;
  final List<int> captured;
  final bool promotes;

  int get to => path.last;

  bool get isCapture => captured.isNotEmpty;

  /// Legal identity of a move: origin, destination and the captured set —
  /// FMJD treats tied sequences over the same pieces as the same choice.
  /// Cached: the AI uses keys heavily for move ordering.
  late final String key = _computeKey();

  String _computeKey() {
    final capturedSorted = [...captured]..sort();
    return '$from>$to:${capturedSorted.join(',')}';
  }

  /// Notation in 1-based FMJD numbering, e.g. `33-28` or `27x38`.
  String get notation {
    final separator = isCapture ? 'x' : '-';
    return '${from + 1}$separator${to + 1}';
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'path': path,
      'captured': captured,
      'promotes': promotes,
    };
  }

  factory Move.fromJson(Map<String, dynamic> json) {
    return Move(
      from: (json['from'] as num).toInt(),
      path: [for (final p in json['path'] as List) (p as num).toInt()],
      captured: [for (final c in json['captured'] as List) (c as num).toInt()],
      promotes: json['promotes'] as bool? ?? false,
    );
  }

  @override
  String toString() => notation;
}
