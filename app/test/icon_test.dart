// Checks the app icon files App Store review and the stores look at. The
// icons come from tool/icon/generate_icon_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/icon/png.dart';

const _iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _rgb = 2;

void main() {
  test('the 1024 App Store icon is 1024 by 1024 RGB with no alpha', () {
    final file = File('$_iosDir/Icon-App-1024x1024@1x.png');
    expect(file.existsSync(), isTrue);
    final header = readPngHeader(file.readAsBytesSync());
    expect(header.width, 1024);
    expect(header.height, 1024);
    // 2 is RGB; 6 (RGBA) and 4 (grey with alpha) are rejected by Apple.
    expect(header.colourType, _rgb);
  });

  test('every icon in Contents.json exists at its pixel size, opaque', () {
    final contents =
        jsonDecode(File('$_iosDir/Contents.json').readAsStringSync())
            as Map<String, dynamic>;
    final images = (contents['images'] as List).cast<Map<String, dynamic>>();
    expect(images, isNotEmpty);
    for (final image in images) {
      final name = image['filename'] as String?;
      expect(name, isNotNull, reason: 'an entry without a file: $image');
      final file = File('$_iosDir/$name');
      expect(file.existsSync(), isTrue, reason: '$name is missing');
      final points = double.parse((image['size'] as String).split('x').first);
      final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
      final px = (points * scale).round();
      final header = readPngHeader(file.readAsBytesSync());
      expect(header.width, px, reason: '$name width');
      expect(header.height, px, reason: '$name height');
      expect(header.colourType, _rgb, reason: '$name has an alpha channel');
    }
  });

  test('the Android adaptive icon and its layers are in place', () {
    const res = 'android/app/src/main/res';
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final xml = File('$res/mipmap-anydpi-v26/$name.xml').readAsStringSync();
      expect(xml, contains('@color/ic_launcher_background'));
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
    }
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    densities.forEach((density, d) {
      final sizes = {
        'ic_launcher': 48 * d,
        'ic_launcher_round': 48 * d,
        'ic_launcher_foreground': 108 * d,
        'ic_launcher_monochrome': 108 * d,
      };
      sizes.forEach((name, px) {
        final file = File('$res/mipmap-$density/$name.png');
        expect(file.existsSync(), isTrue, reason: '$density $name missing');
        final header = readPngHeader(file.readAsBytesSync());
        expect(header.width, px.round(), reason: '$density $name');
        expect(header.height, px.round(), reason: '$density $name');
      });
    });
  });

  test('the web icons listed in the manifest exist at their sizes', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final icon in (manifest['icons'] as List).cast<Map>()) {
      final file = File('web/${icon['src']}');
      expect(file.existsSync(), isTrue, reason: '${icon['src']} missing');
      final px = int.parse((icon['sizes'] as String).split('x').first);
      final header = readPngHeader(file.readAsBytesSync());
      expect(header.width, px, reason: '${icon['src']}');
      expect(header.height, px, reason: '${icon['src']}');
    }
    expect(File('web/favicon.png').existsSync(), isTrue);
  });
}
