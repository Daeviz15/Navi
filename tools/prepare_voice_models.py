"""Stage the pinned English model and generate exact BPE wake-phrase tokens.

Run after downloading the documented archive to build/voice-models/kws.tar.bz2
and installing sentencepiece==0.2.1 in build/voice-tooling.
"""

from pathlib import Path
import hashlib
import json
import shutil
import sys
import tarfile

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build/voice-tooling"))
import sentencepiece as spm

MODEL = "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
ARCHIVE = ROOT / "build/voice-models/kws.tar.bz2"
SOURCE = ROOT / "build/voice-models" / MODEL
DEST = ROOT / "assets/voice/en_small"
DEST.mkdir(parents=True, exist_ok=True)
assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest() == "f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a", "Upstream archive changed"

if not SOURCE.is_dir():
    with tarfile.open(ARCHIVE, "r:bz2") as bundle:
        bundle.extractall(SOURCE.parent, filter="data")

files = {
    "encoder.int8.onnx": "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    "decoder.int8.onnx": "decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    "joiner.int8.onnx": "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
    "tokens.txt": "tokens.txt",
}
for name, upstream in files.items():
    shutil.copyfile(SOURCE / upstream, DEST / name)

tokenizer = spm.SentencePieceProcessor(model_file=str(SOURCE / "bpe.model"))
phrases = ["HEY NAVI", "HI NAVI", "HELLO NAVI"]
vocabulary = {line.rsplit(" ", 1)[0] for line in (DEST / "tokens.txt").read_text(encoding="utf-8").splitlines()}
keywords = []
for phrase in phrases:
    tokens = tokenizer.encode(phrase, out_type=str)
    assert set(tokens) <= vocabulary, (phrase, tokens)
    keywords.append(" ".join(tokens) + " @" + phrase)
(DEST / "keywords.txt").write_text("\n".join(keywords) + "\n", encoding="utf-8")
files["keywords.txt"] = "generated"

manifest = {
    "id": MODEL + "-int8-navi-v1",
    "source": "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/" + MODEL + ".tar.bz2",
    "archiveSha256": hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(),
    "sampleRate": 16000,
    "license": "Apache-2.0 (see upstream model README)",
    "wakePhrases": phrases,
    "files": {
        name: {"bytes": (DEST / name).stat().st_size,
               "sha256": hashlib.sha256((DEST / name).read_bytes()).hexdigest()}
        for name in files
    },
}
(DEST / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("\n".join(keywords))
print(f"Staged {sum((DEST / name).stat().st_size for name in files):,} bytes")
