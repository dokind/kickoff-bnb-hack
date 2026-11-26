import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

web.File _file(Uint8List png, String fileName) =>
    web.File([png.toJS].toJS, fileName, web.FilePropertyBag(type: 'image/png'));

/// Whether this browser's Web Share API takes an image with text: false
/// where `navigator.canShare` is missing (most desktop browsers) or says no.
bool canShareFiles(Uint8List png, String fileName, String text) {
  try {
    return web.window.navigator.canShare(
      web.ShareData(text: text, files: [_file(png, fileName)].toJS),
    );
  } catch (_) {
    return false;
  }
}

/// Downloads [bytes] as [fileName] through a temporary link.
Future<bool> download(Uint8List bytes, String fileName) async {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    // Give the browser time to start the download before the URL goes.
    Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
    return true;
  } catch (_) {
    return false;
  }
}
