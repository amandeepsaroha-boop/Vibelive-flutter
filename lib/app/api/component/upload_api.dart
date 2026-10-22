import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';

/// Strapi media upload (`POST /upload`), shared by profile photos, GST and
/// verification documents. Mutation only: wrap in `useApiMutation` at the
/// call site with the keys that show the new file.
abstract final class UploadApi {
  /// Uploads one file and returns the Strapi media node (`id`, `url`, …).
  static Future<JsonMap> uploadFile(
    String filePath, {
    String? fileName,
    String? mimeType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final name = fileName ?? filePath.split('/').last;
    final form = FormData.fromMap({
      'files': await MultipartFile.fromFile(
        filePath,
        filename: name,
        contentType: DioMediaType.parse(mimeType ?? _mimeFor(name)),
      ),
    });
    final body = await ApiClient.upload(
      '/upload',
      form,
      onProgress: onProgress,
    );
    final first = body is List && body.isNotEmpty
        ? Strapi.map(body.first)
        : null;
    if (first == null || first['id'] == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'errors.upload_failed',
      );
    }
    return first;
  }

  static String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      _ => 'image/${ext.isEmpty ? 'jpeg' : ext}',
    };
  }
}
