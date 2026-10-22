import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Content-addressed, private model staging; no runtime network downloads.
class VoiceModelAssets {
  static const assetRoot = 'assets/voice/en_small';

  Future<String> prepare() async {
    final manifestText = await rootBundle.loadString('$assetRoot/manifest.json');
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    final revision = sha256.convert(utf8.encode(manifestText)).toString();
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/voice/$revision');
    await directory.create(recursive: true);
    final entries = manifest['files'] as Map<String, dynamic>;
    for (final entry in entries.entries) {
      final target = File('${directory.path}/${entry.key}');
      final metadata = entry.value as Map<String, dynamic>;
      if (!await target.exists() || await target.length() != metadata['bytes']) {
        final bytes = await rootBundle.load('$assetRoot/${entry.key}');
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
      }
    }
    await File('${directory.path}/manifest.json').writeAsString(manifestText, flush: true);
    return directory.path;
  }
}
