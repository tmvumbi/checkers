enum PlayerMessageType {
  public('public'),
  private('private');

  const PlayerMessageType(this.value);

  final String value;

  static PlayerMessageType? fromValue(Object? value) {
    return switch (value) {
      'public' => PlayerMessageType.public,
      'private' => PlayerMessageType.private,
      _ => null,
    };
  }
}

/// Admin → player message (kopo parity): public broadcast or private,
/// per-language, visible inside its publish/expiry window.
class PlayerMessage {
  const PlayerMessage({
    required this.id,
    required this.type,
    required this.language,
    required this.publishAt,
    required this.expiresAt,
    required this.enabled,
    this.targetUid,
    this.htmlText,
    this.imageUrl,
    this.linkUrl,
  });

  final String id;
  final PlayerMessageType type;
  final String language;
  final String? targetUid;
  final String? htmlText;
  final String? imageUrl;
  final String? linkUrl;
  final DateTime publishAt;
  final DateTime expiresAt;
  final bool enabled;

  bool get hasText => htmlText != null && htmlText!.trim().isNotEmpty;
  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get hasLink => linkUrl != null && linkUrl!.trim().isNotEmpty;

  bool isActiveAt(DateTime dateTime) {
    final utcDateTime = dateTime.toUtc();
    return enabled &&
        !publishAt.isAfter(utcDateTime) &&
        expiresAt.isAfter(utcDateTime);
  }

  factory PlayerMessage.fromRow(Map<String, dynamic> row) {
    final type = PlayerMessageType.fromValue(row['type']);
    final language = _cleanString(row['language']);
    final publishAt = _parseDateTime(row['publish_at']);
    final expiresAt = _parseDateTime(row['expires_at']);
    final htmlText = _cleanString(row['html_text']);
    final imageUrl = _cleanString(row['image_url']);
    if (type == null ||
        language == null ||
        publishAt == null ||
        expiresAt == null ||
        (htmlText == null && imageUrl == null)) {
      throw const FormatException('Invalid player message.');
    }

    return PlayerMessage(
      id: row['id'] as String,
      type: type,
      language: language,
      targetUid: _cleanString(row['target_uid']),
      htmlText: htmlText,
      imageUrl: imageUrl,
      linkUrl: _cleanString(row['link_url']),
      publishAt: publishAt,
      expiresAt: expiresAt,
      enabled: row['enabled'] == true,
    );
  }

  static PlayerMessage? tryFromRow(Map<String, dynamic> row) {
    try {
      return PlayerMessage.fromRow(row);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static String? _cleanString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}
