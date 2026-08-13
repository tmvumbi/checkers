import 'package:checkers/services/party_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Constructed directly (not via Get.put), so no lifecycle/network runs.
  final service = PartyLinkService();

  group('PartyLinkService.gameIdFromUri', () {
    test('parses https party links', () {
      expect(
        service.gameIdFromUri(
          Uri.parse('https://checkers.contribution.club/party/abc-123'),
        ),
        'abc-123',
      );
    });

    test('parses custom scheme links', () {
      expect(
        service.gameIdFromUri(Uri.parse('checkers://party/xyz')),
        'xyz',
      );
    });

    test('rejects foreign hosts and paths', () {
      expect(
        service.gameIdFromUri(Uri.parse('https://evil.example/party/abc')),
        isNull,
      );
      expect(
        service.gameIdFromUri(
          Uri.parse('https://checkers.contribution.club/other/abc'),
        ),
        isNull,
      );
      expect(
        service.gameIdFromUri(
          Uri.parse('https://checkers.contribution.club/party'),
        ),
        isNull,
      );
    });
  });
}
