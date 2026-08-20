import 'dart:io';

import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/data/models/user_profile.dart';
import 'package:checkers/main.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/profile_photo_service.dart';
import 'package:checkers/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockProfileService extends Mock implements ProfileService {}

class MockPhotoService extends Mock implements ProfilePhotoService {}

class _TestBinding extends Bindings {
  _TestBinding(this.auth, this.profile, this.photo);

  final AuthService auth;
  final ProfileService profile;
  final ProfilePhotoService photo;

  @override
  void dependencies() {
    Get.put<AnalyticsService>(NoopAnalyticsService());
    Get.put<AuthService>(auth);
    Get.put<ProfileService>(profile);
    Get.put<ProfilePhotoService>(photo);
  }
}

const _user = AuthUser(uid: 'uid-1', isAnonymous: true);

// A valid 1x1 transparent PNG so FileImage can decode the local preview.
const _pngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late MockAuthService auth;
  late MockProfileService profile;
  late MockPhotoService photo;
  late File tempImage;

  setUpAll(() async {
    registerFallbackValue(const UserProfile(uid: 'x', nickname: ''));
    tempImage = File(
      '${Directory.systemTemp.path}/checkers_test_avatar.jpg',
    );
    await tempImage.writeAsBytes(_pngBytes);
  });

  setUp(() {
    auth = MockAuthService();
    profile = MockProfileService();
    photo = MockPhotoService();
    when(() => auth.supportsAppleSignIn).thenReturn(false);
    when(() => auth.currentUser).thenReturn(_user);
    when(() => auth.userChanges).thenAnswer((_) => const Stream.empty());
    when(() => profile.getProfile('uid-1')).thenAnswer(
      (_) async => const Success(null),
    );
  });

  tearDown(Get.reset);

  testWidgets('picked photo is uploaded on save and stored on the profile', (
    tester,
  ) async {
    when(() => photo.pickImage()).thenAnswer(
      (_) async => Success(tempImage.path),
    );
    when(() => photo.uploadAvatar('uid-1', tempImage.path)).thenAnswer(
      (_) async => const Success('https://cdn.example/avatar.jpg?v=1'),
    );
    when(() => profile.upsertProfile(any(that: isA<UserProfile>())))
        .thenAnswer(
      (invocation) async => Success(
        invocation.positionalArguments.first as UserProfile,
      ),
    );
    when(() => profile.getProfile('uid-1')).thenAnswer(
      (_) async => const Success(null),
    );

    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(auth, profile, photo),
        initialRoute: '/edit-profile',
      ),
    );
    await tester.pumpAndSettle();

    // Close is hidden on the first-run flow (nothing to go back to).
    expect(find.byKey(const Key('edit-profile-close')), findsNothing);

    await tester.tap(find.byKey(const Key('edit-profile-change-photo')));
    await tester.pumpAndSettle();
    verify(() => photo.pickImage()).called(1);

    await tester.enterText(
      find.byKey(const Key('edit-profile-nickname')),
      'Avatar',
    );
    await tester.tap(find.byKey(const Key('edit-profile-save')));
    await tester.pumpAndSettle();

    verify(() => photo.uploadAvatar('uid-1', tempImage.path)).called(1);
    final saved = verify(
      () => profile.upsertProfile(captureAny(that: isA<UserProfile>())),
    ).captured.single as UserProfile;
    expect(saved.photoUrl, 'https://cdn.example/avatar.jpg?v=1');
    expect(find.byKey(const Key('home-tab-play')), findsOneWidget);
  });

  testWidgets('nothing is uploaded without saving', (tester) async {
    when(() => photo.pickImage()).thenAnswer(
      (_) async => Success(tempImage.path),
    );

    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(auth, profile, photo),
        initialRoute: '/edit-profile',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-profile-change-photo')));
    await tester.pumpAndSettle();

    // Picked but never saved: no upload, no profile write.
    verifyNever(() => photo.uploadAvatar(any(), any()));
    verifyNever(() => profile.upsertProfile(any(that: isA<UserProfile>())));
  });
}
