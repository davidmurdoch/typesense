# Native Alpine providers keep the same public dependency labels as other builds.
package(default_visibility = ["//visibility:public"])

cc_import(name = "crypto_shared", shared_library = "lib/libcrypto.so")
cc_import(name = "ssl_shared", shared_library = "lib/libssl.so")
cc_import(name = "curl_shared", shared_library = "lib/libcurl.so")
cc_import(name = "zlib_shared", shared_library = "lib/libz.so")

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
