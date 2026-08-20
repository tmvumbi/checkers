enum BlockLevel { none, soft, full }

/// Effective block for the signed-in player, as reported by the
/// `sync_device_blocks` RPC (direct blocks plus device-inherited ones).
class BlockStatus {
  const BlockStatus({
    required this.level,
    this.permanent = false,
    this.expiresAt,
  });

  static const BlockStatus none = BlockStatus(level: BlockLevel.none);

  final BlockLevel level;
  final bool permanent;
  final DateTime? expiresAt;

  bool get isBlocked => level != BlockLevel.none;
  bool get canPlay => level == BlockLevel.none;
  bool get canWatch => level != BlockLevel.full;

  factory BlockStatus.fromJson(Map<String, dynamic> json) {
    final level = switch (json['level']) {
      'soft' => BlockLevel.soft,
      'full' => BlockLevel.full,
      _ => BlockLevel.none,
    };
    if (level == BlockLevel.none) {
      return BlockStatus.none;
    }
    final expiresRaw = json['expires_at'];
    final expiresAt = expiresRaw is String
        ? DateTime.tryParse(expiresRaw)?.toLocal()
        : null;
    return BlockStatus(
      level: level,
      permanent: json['permanent'] == true || expiresAt == null,
      expiresAt: expiresAt,
    );
  }
}
