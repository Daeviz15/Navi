import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MapsConfiguration { ready, missing, unsupported }

final mapsConfigurationProvider = FutureProvider<MapsConfiguration>((
  ref,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return MapsConfiguration.unsupported;
  }
  try {
    final configured = await const MethodChannel(
      'navi/maps_configuration',
    ).invokeMethod<bool>('isConfigured');
    return configured == true
        ? MapsConfiguration.ready
        : MapsConfiguration.missing;
  } on PlatformException {
    return MapsConfiguration.missing;
  } on MissingPluginException {
    return MapsConfiguration.missing;
  }
});
