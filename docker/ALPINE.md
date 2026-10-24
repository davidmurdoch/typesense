# Native Alpine Linux builds

The Alpine build targets x86-64 Linux with musl. It uses the same Typesense sources and features as the standard CPU build. CUDA and other architectures are not covered by this configuration.

Prebuilt signed APK packages, OpenRC service setup and release publishing are
documented in [packaging/alpine/README.md](../packaging/alpine/README.md).

Build the native toolchain from the repository root:

```sh
docker build -f docker/alpine-builder.Dockerfile -t typesense-alpine-builder .
```

The builder pins Alpine, GCC, CMake, Perl and the JDK. Bazel 6.2.0 is compiled from its verified source distribution because its published Linux executable requires glibc. The bootstrap patch supplies missing integer headers and Bazel's transition allowlist. Docker BuildKit is required; temporary bootstrap files use memory-backed mounts. Allow at least 12 GiB of memory for building.

Build Typesense and run the portability regression tests:

```sh
docker volume create typesense-alpine-cache
docker run --rm --cpus=4 --memory=14g --memory-swap=14g \
  --mount "type=bind,src=$PWD,dst=/src" \
  --mount type=volume,src=typesense-alpine-cache,dst=/root/.cache \
  -e TYPESENSE_VERSION=30.2 -e TYPESENSE_TARGET=typesense-server \
  typesense-alpine-builder bash -ec '
    bash ci_build_v2.sh --alpine --jobs=4
    bazel test --config=alpine --jobs=4 --test_output=errors //:portability-test
  '
```

The normal `bazel build --config=alpine //:typesense-server` command also works inside the builder. Compiler caching is optional and uses CMake's compiler launcher interface. The build profile does not prescribe cache paths or proxy settings.

Build and check the runtime image:

```sh
docker build -f docker/alpine.Dockerfile -t typesense-alpine dist
bash test/alpine_smoke_test.sh typesense-alpine
```

The smoke test requires Docker, Bash, curl and jq. It checks imports, typo and accent matching, persistence after restart, and execution as a non-root user. The runtime contains the required musl libraries, including libgcc for exception unwinding; it contains no compiler or glibc compatibility layer. Supply `--data-dir`, `--api-key` and other server options when running it normally.

## Dependency patches

Musl-specific build and link settings are selected by `//bazel/config:musl`. bRPC uses POSIX libc interfaces and libunwind on Alpine. Elfutils uses its portable internal helpers with Alpine's argp, fts and obstack libraries. Header fixes support the builder's current GCC, and the RocksDB patch keeps compiler caching away from archive tools.

ONNX Runtime's internal extensions are an explicit, pinned Bazel dependency. Typesense's separately linked tokenizer library uses the `ort_extensions` namespace to avoid collisions with those internal operators. The portability test exercises both tokenizers together, including Unicode inputs and missing-vocabulary behavior, plus bRPC error descriptions and stack capture.

When updating upstream or dependency pins, review patches against the new sources and run both the regular Linux tests and the Alpine workflow. Keep build fixes scoped to the affected dependency and platform.

## Build networks with a private CA

Both Dockerfiles accept the optional BuildKit secret `ca_bundle` (combined public/private PEM roots); the builder also accepts `proxy_ca` (private root for the temporary Java truststore). Forward proxy addresses using Docker's standard proxy build arguments. Secrets and the temporary truststore are not installed in the image. At application build time, pass the relevant proxy and CA environment variables and mount CA files into the container; the Alpine profile forwards them to dependency builds.
