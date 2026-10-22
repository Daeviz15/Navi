import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/android_voice_output.dart';
import '../data/record_microphone.dart';
import '../data/sherpa_speech_engine.dart';
import '../data/voice_preferences.dart';
import '../domain/voice_gateway.dart';

class VoiceServices {
  const VoiceServices({required this.microphone, required this.speech,
    required this.output, required this.preferences});

  final MicrophoneInput Function() microphone;
  final SpeechEngine Function() speech;
  final VoiceGateway Function() output;
  final VoicePreferences preferences;
}

final voiceServicesProvider = Provider<VoiceServices>((ref) => VoiceServices(
  microphone: RecordMicrophone.new,
  speech: SherpaSpeechEngine.new,
  output: AndroidVoiceOutput.new,
  preferences: StoredVoicePreferences(),
));
