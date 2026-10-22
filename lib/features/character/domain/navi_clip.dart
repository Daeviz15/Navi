class NaviClip {
  const NaviClip(this.id, this.videoAsset, this.description, {
    this.frames = 240, this.weight = 1,
    this.cooldown = Duration.zero,
  });
  final String id;
  final String videoAsset;
  final String description;
  final int frames;
  final int weight;
  final Duration cooldown;
  String get animationAsset => 'assets/animations/$id.webp';
  String get posterAsset => id == 'idle_01_sip'
      ? 'assets/images/navi_idle_transparent.png' : 'assets/images/$id.png';
}

abstract final class NaviClips {
  static const sip = NaviClip('idle_01_sip', 'assets/videos/idle/idle_01_sip.mp4',
    'Navi relaxing with a drink', weight: 65);
  static const bored = NaviClip('idle_03_bored_blink', 'assets/videos/idle/idle_03_bored_blink.mp4',
    'Navi looking around and blinking', weight: 25);
  static const daydream = NaviClip('idle_07_daydream', 'assets/videos/idle/idle_07_daydream.mp4',
    'Navi daydreaming', weight: 10, cooldown: Duration(seconds: 35));
  static const sideEye = NaviClip('idle_06_sideeye', 'assets/videos/idle/idle_06_sideeye.mp4',
    'Navi giving a playful side-eye');
  static const listening = NaviClip('listening_02_curious', 'assets/videos/assistant/listening_02_curious.mp4',
    'Navi paying attention to you');
  static const thinking = NaviClip('thinking_01_chin', 'assets/videos/assistant/thinking_01_chin.mp4',
    'Navi preparing a response');
  static const speaking = NaviClip('speaking_01_explaining', 'assets/videos/assistant/speaking_01_explaining.mp4',
    'Navi speaking to you');
  static const smile = NaviClip('happy_01_smile', 'assets/videos/personality_emotions/happy_01_smile.mp4',
    'Navi smiling at you');
  static const idle = [sip, bored, daydream];
  static const all = [sip, bored, daydream, sideEye, listening, thinking, speaking, smile];
}
