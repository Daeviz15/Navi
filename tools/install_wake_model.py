"""Stage a trained Navi microWakeWord v2 model; never invent or relabel weights.

Example:
  python tools/install_wake_model.py hey_navi.json --license LICENSE.model \
    --provenance "Training run URL or dataset/run identifier"

The JSON is an ESPHome microWakeWord v2 export with a local `model` filename,
`wake_word` Hey Navi or Hi Navi, and the exported `micro` inference settings.
This importer labels the result a candidate, not an accuracy-certified model.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/voice/wake_navi'


def install(metadata_path: Path, license_path: Path, provenance: str) -> Path:
    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    if metadata.get('version') != 2:
        raise ValueError('A streaming microWakeWord v2 export is required')
    phrase = ' '.join(metadata['wake_word'].lower().split())
    if phrase not in ['hey navi', 'hi navi', 'hello navi']:
        raise ValueError('The source model must be trained for a Navi greeting')
    # A label is not proof of what weights detect. Preserve source metadata and
    # require provenance so model review can verify training and evaluation.
    model_name = metadata['model']
    if Path(model_name).name != model_name or not model_name.endswith('.tflite'):
        raise ValueError('Use a local model filename, not a URL or nested path')
    model = metadata_path.parent / model_name
    data = model.read_bytes()
    if not 8 <= len(data) <= 2_097_152 or data[4:8] != b'TFL3':
        raise ValueError('Invalid or oversized TFLite flatbuffer')
    license_data = license_path.read_bytes()
    if not license_data.strip() or not provenance.strip():
        raise ValueError('Model license and training provenance are required')
    micro = metadata['micro']
    cutoff = float(micro['probability_cutoff'])
    step = int(micro['feature_step_size'])
    window = int(micro['sliding_window_size'])
    if not math.isfinite(cutoff) or not 0 < cutoff < 1 or not 1 <= step <= 30 or not 1 <= window <= 100:
        raise ValueError('Invalid exported inference settings')
    identity = phrase.replace(' ', '_')
    filename = f'{identity}.tflite'
    DEST.mkdir(parents=True, exist_ok=True)
    path = DEST / 'manifest.json'
    manifest = json.loads(path.read_text()) if path.exists() else {
        'id': 'navi-nah-vee-microwakeword-v2', 'version': 2, 'sampleRate': 16000,
        'validation': 'candidate-not-phone-validated', 'keywords': [], 'files': {},
    }
    manifest['keywords'] = [row for row in manifest['keywords'] if row['file'] != filename]
    manifest['keywords'].append({
        'file': filename, 'phrase': identity.upper(), 'pronunciation': 'NAH-vee',
        'featureStepSizeMs': step, 'probabilityCutoff': cutoff,
        'slidingWindowSize': window, 'provenance': provenance,
    })
    source_name = f'{identity}.source.json'
    license_name = f'{identity}.LICENSE'
    (DEST / filename).write_bytes(data)
    (DEST / source_name).write_bytes(metadata_path.read_bytes())
    (DEST / license_name).write_bytes(license_data)
    for name in [filename, source_name, license_name]:
        content = (DEST / name).read_bytes()
        manifest['files'][name] = {'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)
    return path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('metadata', type=Path)
    parser.add_argument('--license', required=True, type=Path)
    parser.add_argument('--provenance', required=True)
    args = parser.parse_args()
    print(install(args.metadata, args.license, args.provenance))
    print('Candidate installed. Training and recognition accuracy are not certified by this tool.')
