import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';

/// Avatar handling (kopo flow minus the cropper): pick from the gallery,
/// compress to a small JPEG, store at `avatars/{uid}/avatar.jpg`.
abstract class ProfilePhotoService {
  /// Returns a local file path, or null when the user cancelled the picker.
  Future<ApiResult<String?>> pickImage();

  /// Uploads the picked file and returns its public URL (cache-busted).
  Future<ApiResult<String>> uploadAvatar(String uid, String localPath);

  Future<ApiResult<void>> deleteAvatar(String uid);
}

class SupabaseProfilePhotoService implements ProfilePhotoService {
  SupabaseProfilePhotoService({SupabaseClient? client, ImagePicker? picker})
    : _client = client,
      _picker = picker;

  final SupabaseClient? _client;
  final ImagePicker? _picker;

  SupabaseClient get client => _client ?? Supabase.instance.client;
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
  Future<ApiResult<String>> uploadAvatar(String uid, String localPath) async {
    try {
      final compressed = await FlutterImageCompress.compressWithFile(
        localPath,
        minWidth: 512,
        minHeight: 512,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      final bytes = compressed ?? await File(localPath).readAsBytes();
      final path = '$uid/avatar.jpg';
      await client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final url = client.storage.from('avatars').getPublicUrl(path);
      // The path is fixed, so bust image caches per upload.
      return Success('$url?v=${DateTime.now().millisecondsSinceEpoch}');
    } catch (error) {
      return Failure(
        ApiError(code: 'upload-failed', message: error.toString()),
      );
    }
  }

  @override
  Future<ApiResult<void>> deleteAvatar(String uid) async {
    try {
      await client.storage.from('avatars').remove(['$uid/avatar.jpg']);
      return const Success(null);
    } catch (error) {
      return Failure(
        ApiError(code: 'delete-failed', message: error.toString()),
      );
    }
  }
}
