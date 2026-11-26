import 'dart:typed_data';

/// Off the web the system share sheet takes files.
bool canShareFiles(Uint8List png, String fileName, String text) => true;

/// Off the web there is no download.
Future<bool> download(Uint8List bytes, String fileName) async => false;
