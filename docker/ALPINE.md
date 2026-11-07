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
# Create the output directory on the host so it remains writable after the build.
mkdir -p dist
docker volume create typesense-alpine-cache
docker run --rm --cpus=4 --memory=14g --memory-swap=14g \
  --mount "type=bind,src=$PWD,dst=/src" \
  --mount type=volume,src=typesense-alpine-cache,dst=/root/.cache \
  -e TYPESENSE_VERSION=30.2 -e TYPESENSE_TARGET=typesense-server \
  typesense-alpine-builder bash -ec '
    bash ci_build_v2.sh --alpine --jobs=4
    bazel test --config=alpine --jobs=4 --test_output=errors //:portability-test
    packaging/alpine/split-debug.sh dist/typesense-server
  '
```

The normal `bazel build --config=alpine //:typesense-server` command also works inside the builder. Compiler caching is optional and uses CMake's compiler launcher interface. The build profile does not prescribe cache paths or proxy settings.

The split step preserves matching debug information in `dist/typesense-server.debug`
and adds its debug link to the runtime binary before the runtime and package checks.
Before rebuilding, move both files together out of `dist` to retain the matching pair.

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

## System-library experiment

The Alpine candidate uses the installed OpenSSL, libcurl, zlib and GCC runtime.
ICU 71.1 and its full data stay bundled, preserving the production Unicode
dependency. Other platforms retain their bundled dependencies. The builder
pins the matching system headers.

The Alpine workflow's optional compare_baseline input compares the candidate
with published revision 3 on the same runner. It checks shared linkage, fixed
synthetic food/locale queries and reopening baseline data, then reports startup,
import, warm search, memory and executable/APK sizes. The current candidate
requires no additional ICU runtime packages; disk savings include the executable
and retained APK.
The experiment does not publish a release or change production.

The trial pins OpenSSL 3.5.9 because Alpine no longer serves the 3.5.8 development
package. Baseline and candidate timings use the same lab OS packages; these are
experiment results, not approval of a new production package target.

The earlier [all-five shared trial](https://github.com/davidmurdoch/typesense/actions/runs/42382842685)
passed the native runtime/package checks, nine locale comparisons and reopening
baseline-written data. With 1 CPU, 256 MiB and 5,000 synthetic foods, the two runs
per build averaged 0.982 vs 0.994 ms search p50, 1.072 vs 1.084 ms p95 and 1,090
vs 1,093 requests/s with four clients (baseline vs shared). This small trial
showed no meaningful search-speed difference; it is not a production load test.

The executable fell from 117.1 to 75.1 MiB and the APK from 41.0 to 25.0 MiB.
After full ICU data, installed files plus retained packages saved 18.1 MiB per
fleet node at the same OS versions. Process PSS averaged 93.4 vs 105.4 MiB;
startup including Docker launch averaged 3.21 vs 3.31 seconds. The trial does
not isolate which library caused those memory/startup differences.
