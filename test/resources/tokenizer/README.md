# Tokenizer custom-op fixtures

These small, synthetic models exercise the ONNX Runtime extensions `BertTokenizer` operator in the same process as Typesense's standalone tokenizer library. They contain a fourteen-token vocabulary and no trained weights or user data.

`bert.onnx` checks word-piece, accent, Chinese-character and numeric tokenization. `bert_missing_unk.onnx` omits the required `[UNK]` token and checks that the ONNX operator retains its construction error. The standalone tokenizer has different missing-vocabulary behavior; the regression test covers both implementations.

Regenerate with `onnx==1.17.0` installed:

```sh
python3 test/resources/tokenizer/generate.py
```

The models use IR7 and the same custom operator/domain/opset as ONNX Runtime extensions commit `3859b3fd39fdb61761cfe8789e1f0c7d828a31e9`. Run `bazel test //:portability-test`, adding `--config=alpine` in the native Alpine builder.
