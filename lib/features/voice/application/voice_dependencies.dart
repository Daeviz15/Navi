import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/android_voice_output.dart';
import '../data/cloud_http_client.dart';
import '../data/deepseek_voice_agent.dart';
import '../data/groq_speech_engine.dart';
import '../data/record_microphone.dart';
import '../data/voice_preferences.dart';
import '../domain/local_command_router.dart';
import '../domain/voice_gateway.dart';

class VoiceServices {
  const VoiceServices({
    required this.microphone,
    required this.speech,
    required this.output,
    required this.preferences,
    this.reasoner = const LocalCommandRouter(),
    this.wakeRequired = true,
    this.warmSpeech,
    this.coolSpeech,
    this.startupTimeout = const Duration(seconds: 10),
  });

  final MicrophoneInput Function() microphone;
  final SpeechEngine Function() speech;
  final VoiceGateway Function() output;
  final VoicePreferences preferences;
  final VoiceReasoner reasoner;
  final bool wakeRequired;
  final Future<void> Function()? warmSpeech;
  final void Function()? coolSpeech;
  final Duration startupTimeout;
}

final voiceServicesProvider = Provider<VoiceServices>((ref) {
  // Share a single persistent keep-alive HTTP transport across STT, LLM, and
  // Orpheus TTS so TLS 1.3 sockets to api.groq.com stay warm across turns.
  final sharedHttp = DartIoCloudHttpTransport();
  final agent = DeepSeekVoiceAgent(http: sharedHttp, useLocalFastPath: true);
  ref.onDispose(() {
    agent.dispose();
    sharedHttp.close();
  });

  return VoiceServices(
    microphone: RecordMicrophone.new,
    speech: () => GroqSpeechEngine(http: sharedHttp),
    output: () => AndroidVoiceOutput(http: sharedHttp),
    preferences: StoredVoicePreferences(),
    reasoner: agent,
    wakeRequired: false,
  );
});
