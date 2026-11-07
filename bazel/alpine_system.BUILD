# Native Alpine providers keep the same public dependency labels as other builds.
package(default_visibility = ["//visibility:public"])

cc_import(name = "crypto_shared", shared_library = "lib/libcrypto.so")
cc_import(name = "ssl_shared", shared_library = "lib/libssl.so")
cc_import(name = "curl_shared", shared_library = "lib/libcurl.so")
cc_import(name = "zlib_shared", shared_library = "lib/libz.so")
cc_import(name = "icu_i18n_shared", shared_library = "lib/libicui18n.so")
cc_import(name = "icu_common_shared", shared_library = "lib/libicuuc.so")
cc_import(name = "icu_data_shared", shared_library = "lib/libicudata.so")

cc_library(
    name = "openssl",
    hdrs = glob(["include/openssl/*.h"]),
    includes = ["include"],
    deps = [":ssl_shared", ":crypto_shared"],
)

cc_library(
    name = "curl",
    hdrs = glob(["include/curl/*.h"]),
    includes = ["include"],
    deps = [":curl_shared"],
)

cc_library(
    name = "zlib",
    hdrs = ["include/zlib.h", "include/zconf.h"],
    includes = ["include"],
    deps = [":zlib_shared"],
)

cc_library(
    name = "icu",
    hdrs = glob(["include/unicode/*.h"]),
    includes = ["include"],
    deps = [":icu_i18n_shared", ":icu_common_shared", ":icu_data_shared"],
)
