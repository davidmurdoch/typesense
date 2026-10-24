load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)

configure_make(
    name = "libdw",
    configure_options = [
        "--disable-libdebuginfod",
        "--disable-debuginfod",
        "--without-lzma",
        "--without-bzlib",
        "--without-zstd"
    ],
    env = select({
        "@//bazel/config:musl": {
            "CFLAGS": "-O2 -Wno-error=unterminated-string-initialization",
            "CXXFLAGS": "-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3",
        },
        "//conditions:default": {},
    }),
    lib_source = "//:all_srcs",
    out_lib_dir = "lib",
    out_static_libs = ["libdw.a", "libelf.a"] + select({
        "@//bazel/config:musl": ["libeu.a"],
        "//conditions:default": [],
    }),
    # libdw needs the portable error() implementation from its internal helper archive.
    postfix_script = select({
        "@//bazel/config:musl": "cp $BUILD_TMPDIR/lib/libeu.a $INSTALLDIR/lib/",
        "//conditions:default": "",
    }),
    args = ["-j4"],
    linkopts = select({
        "@//bazel/config:musl": ["-largp", "-lfts", "-lobstack"],
        "//conditions:default": [],
    }),
    deps = [
        "@com_github_madler_zlib//:zlib",
    ],
)
