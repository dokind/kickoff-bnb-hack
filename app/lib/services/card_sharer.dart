import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import 'card_file_stub.dart'
    if (dart.library.js_interop) 'card_file_web.dart'
    as file;

/// How a share of the round's card ended.
enum ShareOutcome {
  /// The system share sheet took the image (or, on the web, the browser's).
  shared,

  /// The person closed the share sheet without picking anything.
  dismissed,

  /// This browser cannot share an image: the PNG was downloaded instead.
  downloaded,
}

/// Hands the round's card to the platform: the share sheet on a phone, the
/// Web Share API in a browser. Behind an interface so tests never reach a
/// platform channel.
abstract class CardSharer {
  /// Whether the image can also be saved as a file from here (the web).
  bool get canSave;

  /// Shares [png] (named [fileName]) with [text] beside it. [origin] is the
  /// button pressed, which an iPad's share popover points at. Throws when
  /// nothing could be shared or saved.
  Future<ShareOutcome> share({
    required Uint8List png,
    required String fileName,
    required String text,
    Rect? origin,
  });

  /// Saves [png] as [fileName] (a download in the browser). False where
  /// there is no such thing.
  Future<bool> save(Uint8List png, String fileName);
}

/// The [CardSharer] the app uses: share_plus, with a download in a browser
/// that cannot share files.
class PlatformCardSharer implements CardSharer {
  const PlatformCardSharer();

  @override
  bool get canSave => kIsWeb;

  @override
  Future<ShareOutcome> share({
    required Uint8List png,
    required String fileName,
    required String text,
    Rect? origin,
  }) async {
    if (kIsWeb && !file.canShareFiles(png, fileName, text)) {
      return _download(png, fileName);
    }
    final ShareResult result;
    try {
      result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
          fileNameOverrides: [fileName],
          sharePositionOrigin: origin,
          // The fallbacks are ours (below), so the outcome is known.
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (kIsWeb) return _download(png, fileName);
      rethrow;
    }
    return result.status == ShareResultStatus.dismissed
        ? ShareOutcome.dismissed
        : ShareOutcome.shared;
  }

  Future<ShareOutcome> _download(Uint8List png, String fileName) async {
    if (!await file.download(png, fileName)) {
      throw StateError('The image could not be downloaded.');
    }
    return ShareOutcome.downloaded;
  }

  @override
  Future<bool> save(Uint8List png, String fileName) =>
      file.download(png, fileName);
}

/// The sharer the share sheet uses unless it is given one. Tests replace it.
CardSharer cardSharer = const PlatformCardSharer();
