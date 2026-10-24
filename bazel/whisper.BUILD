load("@rules_foreign_cc//foreign_cc:defs.bzl", "cmake")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "whisper_srcs",
    srcs = glob(["**"]),
)

config_setting(
    name = "with_cuda",
    define_values = { "use_cuda": "on" }
)

print("CUDA: " + str(select({
    ":with_cuda": True,
    "//conditions:default": False,
})))

load("@cuda_home_repo//:cuda_home.bzl", "CUDA_HOME")

CMAKE_CACHE_ENTRIES = {
    "BUILD_SHARED_LIBS": "OFF",
    "WHISPER_BUILD_EXAMPLES": "OFF",
    "WHISPER_BUILD_TESTS": "OFF",
    "CMAKE_POSITION_INDEPENDENT_CODE": "ON",
}

CMAKE_MUSL_CACHE_ENTRIES = dict(
    CMAKE_CACHE_ENTRIES,
    WHISPER_NO_AVX = "ON",
    WHISPER_NO_AVX2 = "ON",
    WHISPER_NO_FMA = "ON",
    WHISPER_NO_F16C = "ON",
)

cmake(
    name = "whisper",
    cache_entries = select({
        "@//bazel/config:musl": CMAKE_MUSL_CACHE_ENTRIES,
        "//conditions:default": CMAKE_CACHE_ENTRIES,
    }),
    build_args = [
        "--", "-j8"
    ],
    lib_source = "//:whisper_srcs",
    out_static_libs = ["static/libwhisper.a"],
    tags=["requires-network","no-sandbox"],
)

cc_library(
    name = "whisper_headers",
    hdrs = glob(["*.h"]),
    visibility = ["//visibility:public"]
)

load("@cuda_home_repo//:cuda_home.bzl", "CUDA_HOME")
load("@cuda_home_repo//:cudnn_home.bzl", "CUDNN_HOME")
load("@rules_cuda//cuda:defs.bzl", "cuda_library")

cc_shared_library(
    name = "whisper_cuda_shared",
    deps = [":whisper_cuda", ":whisper"],
    visibility = ["//visibility:public"],
    user_link_flags = ["-lcudart",
            "-lcublas",
            "-lcuda",
            "-L" + CUDA_HOME + "/lib64",
    ]
)

cc_library(
    name = "ggml",
    srcs = ["ggml.c", "ggml-quants.c", "ggml-backend.c", "ggml-alloc.c"],
    deps = [":whisper_headers"],
)


cuda_library(
    name = "whisper_cuda", 
    srcs = ["ggml-cuda.cu", 
            "ggml-cuda.h", 
            "ggml.h", 
            "ggml-impl.h", 
            "ggml-backend.h", 
            "ggml-alloc.h", 
            "ggml-backend-impl.h"],
)
