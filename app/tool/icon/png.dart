import 'dart:io';
import 'dart:typed_data';

/// A minimal PNG encoder, so the icon generator controls the colour type:
/// RGB (type 2) for the App Store, where an alpha channel is rejected, and
/// RGBA (type 6) for Android and web layers that need transparency.
///
/// [rgba] is straight (not premultiplied) RGBA, 4 bytes a pixel, row by row.
Uint8List encodePng(
  Uint8List rgba,
  int width,
  int height, {
  required bool alpha,
}) {
  final bpp = alpha ? 4 : 3;
  final stride = width * bpp;
  final raw = Uint8List((stride + 1) * height);
  final row = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 4;
      final d = x * bpp;
      row[d] = rgba[s];
      row[d + 1] = rgba[s + 1];
      row[d + 2] = rgba[s + 2];
      if (alpha) row[d + 3] = rgba[s + 3];
    }
    // Filter 1 ("Sub"): each byte minus the same channel one pixel left.
    // Smooth gradients then compress far better than unfiltered rows.
    final o = y * (stride + 1);
    raw[o] = 1;
    for (var i = 0; i < stride; i++) {
      final left = i >= bpp ? row[i - bpp] : 0;
      raw[o + 1 + i] = (row[i] - left) & 0xFF;
    }
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, alpha ? 6 : 2) // colour type
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(ZLibCodec(level: 9).encode(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final len = ByteData(4)..setUint32(0, data.length);
  out
    ..add(len.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  out.add(crc.buffer.asUint8List());
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Width, height and colour type from a PNG's IHDR chunk.
({int width, int height, int colourType}) readPngHeader(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw const FormatException('Not a PNG');
  }
  final data = ByteData.sublistView(bytes);
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    throw const FormatException('IHDR is not the first chunk');
  }
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colourType: data.getUint8(25),
  );
}
