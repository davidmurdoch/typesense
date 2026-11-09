load("@rules_foreign_cc//foreign_cc:defs.bzl", "configure_make")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_srcs",
    srcs = glob(["**"]),
    visibility = ["//visibility:public"],
)

configure_make(
    name = "icu_bundled",
    args = ["-j8"],
    configure_command = "icu4c/source/runConfigureICU",
    configure_options = select({
        "@platforms//os:linux": ["Linux"],
        "@platforms//os:macos": ["MacOSX"],
    }) + [
        "--enable-static",
        "--disable-shared",
    ],
    lib_source = ":all_srcs",
    out_static_libs = [
        "libicui18n.a",
        "libicutu.a",
        "libicuuc.a",
        "libicudata.a",
        "libicuio.a",
    ],
)

cc_library(
    name = "icu_system",
    linkopts = ["-licui18n", "-licuuc", "-licudata"],
)

alias(
    name = "icu",
    actual = select({
        "@//bazel/config:musl": ":icu_system",
        "//conditions:default": ":icu_bundled",
    }),
    visibility = ["//visibility:public"],
)
