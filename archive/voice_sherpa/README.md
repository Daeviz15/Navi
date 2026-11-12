# Previous Sherpa implementation

These source snapshots preserve the previous recognizer and desktop benchmarks.
They are stored as `.dart.txt` so they do not require the removed Sherpa package
or compile into the app. The original model assets and preparation scripts are
also preserved, but the Sherpa models are no longer bundled in the shipping app.

The default Android engine is now Moonshine Tiny Streaming English. Shipping
both SDKs without isolation is unsafe: both provide `libonnxruntime.so`.
Do not resolve that conflict with an arbitrary `pickFirst` rule. Restoring
Sherpa requires a deliberate backend/dependency change and new validation.

The historical benchmark results do not measure the new engine or phone accuracy.
