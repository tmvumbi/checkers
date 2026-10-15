import 'package:checkers/services/party_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Constructed directly (not via Get.put), so no lifecycle/network runs.
  final service = PartyLinkService();

  group('PartyLinkService.gameIdFromUri', () {
    test('parses https party links', () {
      expect(
        service.gameIdFromUri(Uri.parse('https://dame.cd/party/abc-123')),
        'abc-123',
      );
    });

    test('parses custom scheme links', () {
      expect(service.gameIdFromUri(Uri.parse('dame://party/xyz')), 'xyz');
    });

    test('rejects unregistered schemes and hosts', () {
      expect(
        service.gameIdFromUri(Uri.parse('legacy-checkers://party/xyz')),
        isNull,
      );
      expect(service.gameIdFromUri(Uri.parse('checkers://party/xyz')), isNull);
      expect(
        service.gameIdFromUri(
          Uri.parse('https://legacy.example/party/old-link'),
        ),
        isNull,
      );
    });

    test('recognizes tournament links on dame.cd schemes', () {
      expect(service.isTournamentUri(Uri.parse('dame://tournament')), isTrue);
      expect(
        service.isTournamentUri(Uri.parse('checkers://tournament')),
        isFalse,
      );
      expect(
        service.isTournamentUri(Uri.parse('https://dame.cd/tournament')),
        isTrue,
      );
    });

    test('rejects foreign hosts and paths', () {
      expect(
        service.gameIdFromUri(Uri.parse('https://evil.example/party/abc')),
        isNull,
      );
      expect(
        service.gameIdFromUri(Uri.parse('https://dame.cd/other/abc')),
        isNull,
      );
      expect(service.gameIdFromUri(Uri.parse('https://dame.cd/party')), isNull);
    });
  });
}
