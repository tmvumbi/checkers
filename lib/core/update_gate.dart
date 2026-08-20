/// Force-update gate evaluation (PRD §8): the backend lists the ACTIVE
/// versions per platform plus the platform's store link. A version missing
/// from its platform's list must update. Missing or empty lists fail open —
/// a config problem must never lock players out.
class UpdateGate {
  const UpdateGate({required this.updateRequired, this.storeUrl});

  final bool updateRequired;
  final String? storeUrl;

  static UpdateGate evaluate(
    Map<String, dynamic> config, {
    required bool isIOS,
    required String currentVersion,
  }) {
    final listKey = isIOS ? 'allowed_ios_versions' : 'allowed_android_versions';
    final urlKey = isIOS ? 'ios_app_url' : 'android_app_url';
    final url = config[urlKey] as String?;
    final rawList = config[listKey];
    if (rawList is! List || rawList.isEmpty) {
      return UpdateGate(updateRequired: false, storeUrl: url);
    }
    final allowed = rawList.map((v) => v.toString()).toSet();
    return UpdateGate(
      updateRequired: !allowed.contains(currentVersion),
      storeUrl: url,
    );
  }
}
