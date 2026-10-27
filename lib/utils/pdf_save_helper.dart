import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Saves a PDF into the public Downloads folder.
//
// Android 11 and newer (API 30+): written through MediaStore (scoped
// storage), so no storage permission is needed and no prompt is shown.
// Android 9 and older (API 28-): MediaStore has no effect there, so the file
// is written directly and the legacy storage permission is requested first.
//
// Returns true on success. On failure it returns false and the caller falls
// back to the share sheet. The real exception is only logged in debug builds.
Future<bool> savePdfToDownloads(Uint8List bytes, String filename) async {
  if (!Platform.isAndroid) return false;
  try {
    await MediaStore.ensureInitialized();
    // Required by the plugin even when saving to the Downloads root.
    MediaStore.appFolder = 'KarYab';

    final sdk = await MediaStore().getPlatformSDKInt();
    if (sdk <= 28) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        _log('storage permission denied on API $sdk');
        return false;
      }
    }

    // The plugin copies from a file path, so stage the bytes in the app's
    // temp folder first (the plugin removes the staged file afterwards).
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsBytes(bytes, flush: true);

    final info = await MediaStore().saveFile(
      tempFilePath: tempFile.path,
      dirType: DirType.download,
      dirName: DirName.download,
      relativePath: FilePath.root,
    );
    if (info == null) {
      _log('MediaStore.saveFile returned null on API $sdk');
      return false;
    }
    return true;
  } catch (e, st) {
    _log('save failed: ${e.runtimeType}: $e\n$st');
    return false;
  }
}

void _log(String message) {
  if (kDebugMode) debugPrint('[pdf_save_helper] $message');
}
