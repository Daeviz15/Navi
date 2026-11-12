"""Download only pinned int8 English command-ASR files, never during app use."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/voice/en_commands'
REPO = 'csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17'
REVISION = 'd42f2d9f7ca24806fb667456a18a9f1b60f70d16'
FILES = {
    'encoder.int8.onnx': ('encoder-epoch-99-avg-1.int8.onnx', '3810755ce7c3ab26b42a8bcf39d191308fa27fb0f53358823ba46141d03b7eb3'),
    'decoder.int8.onnx': ('decoder-epoch-99-avg-1.int8.onnx', '21e2a2acd961b3ac72f55be2f10f1a285e1b0b0ba010d7c0b6eab141411b163c'),
    'joiner.int8.onnx': ('joiner-epoch-99-avg-1.int8.onnx', 'e085d73b593cf9b0707f370dbd656d58327d3fe36d80d849202ef81df02cb01e'),
    'tokens.txt': ('tokens.txt', None),
    'UPSTREAM_README.md': ('README.md', None),
}
DEST.mkdir(parents=True, exist_ok=True)
for target, (source, expected) in FILES.items():
    file = DEST / target
    if not file.exists() or expected is None or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
        temporary = file.with_suffix(file.suffix + '.tmp')
        with urllib.request.urlopen(f'https://huggingface.co/{REPO}/resolve/{REVISION}/{source}', timeout=90) as response:
            with temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
        if expected and hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Hash mismatch: {source}')
        temporary.replace(file)
    print(f'{target}: {file.stat().st_size:,} bytes', flush=True)
shutil.copyfile(ROOT / 'assets/voice/en_small/LICENSE', DEST / 'LICENSE')
manifest = {
    'id': 'zipformer-en-20m-int8-navi-v1',
    'source': f'https://huggingface.co/{REPO}',
    'revision': REVISION,
    'sampleRate': 16000,
    'license': 'Apache-2.0',
    'files': {name: {'bytes': (DEST / name).stat().st_size,
                      'sha256': hashlib.sha256((DEST / name).read_bytes()).hexdigest()}
              for name in FILES if name != 'UPSTREAM_README.md'},
}
(DEST / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
