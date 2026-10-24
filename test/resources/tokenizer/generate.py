"""Regenerate the small custom-op fixtures with onnx==1.17.0."""
from pathlib import Path
from onnx import TensorProto, checker, helper

vocab = "[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\nhello\nworld\ncafe\nplay\n##ing\n!\n中\n文\n2\n"
for name, words in [("bert", vocab), ("bert_missing_unk", vocab.replace("[UNK]\n", ""))]:
    node = helper.make_node(
        "BertTokenizer", ["text"], ["input_ids", "token_type_ids", "attention_mask"],
        domain="ai.onnx.contrib", vocab_file=words, do_lower_case=1, strip_accents=1,
    )
    graph = helper.make_graph(
        [node], name,
        [helper.make_tensor_value_info("text", TensorProto.STRING, [1])],
        [helper.make_tensor_value_info(output, TensorProto.INT64, [None])
         for output in ["input_ids", "token_type_ids", "attention_mask"]],
    )
    model = helper.make_model(
        graph, producer_name="typesense-test", ir_version=7,
        opset_imports=[helper.make_opsetid("ai.onnx", 14), helper.make_opsetid("ai.onnx.contrib", 1)],
    )
    checker.check_model(model)
    Path(__file__).with_name(name + ".onnx").write_bytes(model.SerializeToString())
