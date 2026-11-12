"""Vendor the pinned Apache-2.0 Android microWakeWord runtime (no models).

Run with Python 3.11+. Inference dependencies are separately pinned by URL and
SHA-256 in the upstream CMakeLists.txt. Downloads happen only during builds.
"""
from pathlib import Path
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REVISION = '023390ba94333d05876304238b2297ffe1df97e2'
SOURCE = f'https://raw.githubusercontent.com/home-assistant/android/{REVISION}'
CPP = ROOT / 'android/app/src/main/cpp/microwakeword'
KOTLIN = ROOT / 'android/app/src/main/kotlin/io/homeassistant/companion/android/microwakeword'
files = {}
for name in ['CMakeLists.txt', 'Logging.h', 'MicroFrontendWrapper.cpp',
             'MicroFrontendWrapper.h', 'MicroWakeWordEngine.cpp',
             'MicroWakeWordEngine.h', 'MicroWakeWord_jni.cpp', 'MicroWakeWord.kt',
             'LICENSE.md']:
    if name == 'LICENSE.md':
        relative = name
        target = CPP / 'LICENSE'
    elif name.endswith('.kt'):
        relative = 'microwakeword/src/main/kotlin/io/homeassistant/companion/android/microwakeword/' + name
        target = KOTLIN / name
    else:
        relative = 'microwakeword/src/main/cpp/' + name
        target = CPP / name
    with urllib.request.urlopen(f'{SOURCE}/{relative}', timeout=60) as response:
        original = response.read()
    text = original.decode('utf-8')
    if name == 'CMakeLists.txt':
        # Sanitizer builds require a specially configured phone/runtime. Keep
        # ordinary debug APKs runnable on the user's unmodified Android phone.
        text = text[:text.index('# HWAddressSanitizer')]
        text = text.replace('include(FetchContent)',
                            'set(CMAKE_POLICY_DEFAULT_CMP0135 NEW)\ninclude(FetchContent)')
    elif name.endswith('.kt'):
        text = text.replace('import timber.log.Timber\n', '')
        text = text.replace('Timber.d(', 'android.util.Log.d("NaviWake", ')
        text = text.replace('android.util.Log.d("NaviWake", "Loaded microwakeword native library")',
                            'android.util.Log.d("NaviWake", "Loaded microwakeword native library")\n            Unit')
        # Native inference is always closed on the owner executor; a GC finalizer
        # could race processAudio on another thread and dereference freed memory.
        start = text.index('    /**\n     * Safety net')
        end = text.index('    private companion object', start)
        text = text[:start] + text[end:]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')
    files[str(target.relative_to(ROOT)).replace('\\', '/')] = {
        'upstreamSha256': hashlib.sha256(original).hexdigest(),
        'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
    }
manifest = {'repository': 'https://github.com/home-assistant/android',
            'revision': REVISION, 'license': 'Apache-2.0', 'files': files}
(CPP / 'upstream.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
notices = ROOT / 'assets/voice/wake_navi'
notices.mkdir(parents=True, exist_ok=True)
(notices / 'LICENSE.runtime').write_bytes((CPP / 'LICENSE').read_bytes())
# Apache-2.0 dependencies share LICENSE.runtime; preserve KissFFT's separate
# copyright and BSD license as well. None of these files grants model rights.
for upstream, name in [
    ('https://raw.githubusercontent.com/mborgerding/kissfft/7bce4153c6bc8aba2db0e889e576f9d00505cbe1/COPYING', 'COPYING.kissfft'),
    ('https://raw.githubusercontent.com/mborgerding/kissfft/7bce4153c6bc8aba2db0e889e576f9d00505cbe1/LICENSES/BSD-3-Clause', 'LICENSE.kissfft'),
]:
    with urllib.request.urlopen(upstream, timeout=40) as response:
        (notices / name).write_bytes(response.read())
print('Prepared pinned microWakeWord native runtime. No custom wake model is included.')
