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
        service.gameIdFromUri(
          Uri.parse('club.contribution.checkers://party/xyz'),
        ),
        'xyz',
      );
    });

    test('still parses the legacy scheme shared before the rename', () {
      expect(
        service.gameIdFromUri(Uri.parse('checkers://party/xyz')),
        'xyz',
      );
    });

    test('recognizes tournament links on both schemes', () {
      expect(
        service.isTournamentUri(
          Uri.parse('club.contribution.checkers://tournament'),
        ),
        isTrue,
      );
      expect(
        service.isTournamentUri(Uri.parse('checkers://tournament')),
        isTrue,
      );
      expect(
        service.isTournamentUri(
          Uri.parse('https://checkers.contribution.club/tournament'),
        ),
        isTrue,
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
