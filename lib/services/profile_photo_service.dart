import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import 'convex/convex_gateway.dart';

/// Avatar handling (kopo flow minus the cropper): pick from the gallery,
/// compress to a small JPEG, store it as the player's avatar.
abstract class ProfilePhotoService {
  /// Returns a local file path, or null when the user cancelled the picker.
  Future<ApiResult<String?>> pickImage();

  /// Uploads the picked file and returns its public URL (cache-busted).
  Future<ApiResult<String>> uploadAvatar(String uid, String localPath);

  Future<ApiResult<void>> deleteAvatar(String uid);
}

/// Uploads with a Convex storage upload URL; the backend keeps one avatar
/// file per profile and deletes the previous one.
class ConvexProfilePhotoService implements ProfilePhotoService {
  ConvexProfilePhotoService({
    ConvexGateway? gateway,
    ImagePicker? picker,
    Future<String> Function(Uri uploadUrl, List<int> bytes)? postFile,
  }) : _gatewayOverride = gateway,
       _picker = picker,
       _postFile = postFile ?? _postWithHttpClient;

  final ConvexGateway? _gatewayOverride;
  final ImagePicker? _picker;
  final Future<String> Function(Uri uploadUrl, List<int> bytes) _postFile;

  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();
  ImagePicker get picker => _picker ?? ImagePicker();

  @override
  Future<ApiResult<String?>> pickImage() async {
    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      return Success(picked?.path);
    } catch (error) {
      return Failure(ApiError(code: 'pick-failed', message: error.toString()));
    }
  }

  @override
  Future<ApiResult<String>> uploadAvatar(String uid, String localPath) {
    return guardConvex(() async {
      final compressed = await FlutterImageCompress.compressWithFile(
        localPath,
        minWidth: 512,
        minHeight: 512,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      final bytes = compressed ?? await File(localPath).readAsBytes();
      final uploadUrl =
          await _convex.mutation('profiles:generateAvatarUploadUrl') as String;
      final storageId = await _postFile(Uri.parse(uploadUrl), bytes);
      final url = await _convex.mutation('profiles:setAvatar', {
        'storageId': storageId,
      });
      if (url is! String) {
        throw StateError('upload-failed');
      }
      return url;
    });
  }

  @override
  Future<ApiResult<void>> deleteAvatar(String uid) => guardConvex(() async {
    await _convex.mutation('profiles:removeAvatar');
  });

  static Future<String> _postWithHttpClient(Uri url, List<int> bytes) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType('image', 'jpeg');
      request.add(bytes);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('upload failed (${response.statusCode}): $body');
      }
      return (jsonDecode(body) as Map)['storageId'] as String;
    } finally {
      client.close();
    }
  }
}
