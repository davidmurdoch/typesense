#include <gtest/gtest.h>
#include <array>
#include <cerrno>
#include <string>
#include <vector>
#include <butil/errno.h>
#include <butil/debug/stack_trace.h>
#ifdef TYPESENSE_TEST_ORT_EXTENSIONS
#include <core/session/onnxruntime_cxx_api.h>
#endif
#include <tokenizer/bert_tokenizer.hpp>

namespace {

const std::string vocab = "[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\nhello\nworld\ncafe\nplay\n##ing\n!\n中\n文\n2\n";
const char* text = "HELLO Café playing!中文 2";
const std::vector<int64_t> expected_ids = {2, 5, 7, 8, 9, 10, 11, 12, 13, 3};

#ifdef TYPESENSE_TEST_ORT_EXTENSIONS
std::string model_path(const std::string& name) {
    return std::string(ROOT_DIR) + "test/resources/tokenizer/" + name + ".onnx";
}
#endif

}

TEST(PortabilityTest, StandaloneTokenizerPreservesWordpieceAndUnicode) {
    using ort_extensions::ustring;
    ort_extensions::BertTokenizer tokenizer(
        vocab, true, true, ustring("[UNK]"), ustring("[SEP]"), ustring("[PAD]"),
        ustring("[CLS]"), ustring("[MASK]"), true, true, ustring("##"), 512, "longest_first");
    auto ids = tokenizer.Encode(tokenizer.Tokenize(ustring(text)));
    EXPECT_EQ(expected_ids, tokenizer.AddSpecialToken(ids));

    ort_extensions::BertTokenizerVocab words(vocab);
    testing::internal::CaptureStdout();
    EXPECT_EQ(-1, words.FindTokenId(ustring("not-in-vocabulary")));
    EXPECT_NE(std::string::npos, testing::internal::GetCapturedStdout().find("not-in-vocabulary"));
}

#ifdef TYPESENSE_TEST_ORT_EXTENSIONS
TEST(PortabilityTest, OnnxAndStandaloneTokenizersCoexist) {
    Ort::Env env(ORT_LOGGING_LEVEL_ERROR, "tokenizer-test");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1);
    options.SetInterOpNumThreads(1);
    options.EnableOrtCustomOps();
    Ort::Session session(env, model_path("bert").c_str(), options);
    Ort::AllocatorWithDefaultOptions allocator;
    const std::array<int64_t, 1> shape = {1};
    auto input = Ort::Value::CreateTensor(allocator, shape.data(), shape.size(), ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING);
    input.FillStringTensor(&text, 1);
    const char* inputs[] = {"text"};
    const char* outputs[] = {"input_ids", "token_type_ids", "attention_mask"};
    auto result = session.Run(Ort::RunOptions{nullptr}, inputs, &input, 1, outputs, 3);
    ASSERT_EQ(3, result.size());
    for (size_t i = 0; i < result.size(); i++) {
        const auto size = result[i].GetTensorTypeAndShapeInfo().GetElementCount();
        const auto* data = result[i].GetTensorData<int64_t>();
        const std::vector<int64_t> actual(data, data + size);
        EXPECT_EQ(i == 0 ? expected_ids : std::vector<int64_t>(expected_ids.size(), i == 1 ? 0 : 1), actual);
    }
}

TEST(PortabilityTest, OnnxPreservesMissingVocabularyError) {
    Ort::Env env(ORT_LOGGING_LEVEL_ERROR, "tokenizer-test");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1);
    options.EnableOrtCustomOps();
    EXPECT_THROW({ Ort::Session session(env, model_path("bert_missing_unk").c_str(), options); }, Ort::Exception);
}

#endif

TEST(PortabilityTest, CustomizedErrnoDoesNotMistakeMuslUnknownErrorsForSystemErrors) {
    testing::internal::CaptureStderr();
    EXPECT_EQ(0, butil::DescribeCustomizedErrno(30001, "EPORTABILITY_TEST", "portability test error"));
    EXPECT_TRUE(testing::internal::GetCapturedStderr().empty());
    EXPECT_STREQ("portability test error", berror(30001));
    errno = EBUSY;
    const std::string unknown = berror(30002);
    const int saved_errno = errno;
    EXPECT_EQ("Unknown error 30002", unknown);
    EXPECT_EQ(EBUSY, saved_errno);
    EXPECT_STRNE("Unknown error 2", berror(ENOENT));
}

TEST(PortabilityTest, NativeStackTraceCapturesFrames) {
    butil::debug::StackTrace trace;
    size_t count = 0;
    EXPECT_NE(nullptr, trace.Addresses(&count));
    EXPECT_GT(count, 0);
    EXPECT_FALSE(trace.ToString().empty());
}
