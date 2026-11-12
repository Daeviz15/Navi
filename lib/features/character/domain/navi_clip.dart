/// Semantic descriptor for a companion behavior state or idle variation.
class NaviClip {
  const NaviClip(
    this.id,
    this.description, {
    this.weight = 1,
    this.cooldown = Duration.zero,
  });

  final String id;
  final String description;
  final int weight;
  final Duration cooldown;
}

abstract final class NaviClips {
  static const sip = NaviClip(
    'idle_01_sip',
    'Navi resting calmly',
    weight: 65,
  );
  static const bored = NaviClip(
    'idle_03_bored_blink',
    'Navi drifting gently',
    weight: 25,
  );
  static const daydream = NaviClip(
    'idle_07_daydream',
    'Navi daydreaming softly',
    weight: 10,
    cooldown: Duration(seconds: 35),
  );
  static const sideEye = NaviClip(
    'idle_06_sideeye',
    'Navi rippling playfully',
  );
  static const listening = NaviClip(
    'listening_01_attentive',
    'Navi paying attention to you',
  );
  static const thinking = NaviClip(
    'thinking_01_chin',
    'Navi preparing a response',
  );
  static const speaking = NaviClip(
    'speaking_01_explaining',
    'Navi speaking to you',
  );
  static const smile = NaviClip(
    'happy_01_smile',
    'Navi pulsing warmly at you',
  );

  static const idle = [sip, bored, daydream];
  static const all = [
    sip,
    bored,
    daydream,
    sideEye,
    listening,
    thinking,
    speaking,
    smile,
  ];
}
