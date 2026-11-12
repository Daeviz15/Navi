# JNI_OnLoad registers methods against this exact upstream class name.
-keep class io.homeassistant.companion.android.microwakeword.MicroWakeWord { *; }
# JNI looks up these model/result classes and fields by their upstream names.
-keep class ai.moonshine.voice.** { *; }
