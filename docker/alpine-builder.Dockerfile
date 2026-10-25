# syntax=docker/dockerfile:1
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

ARG BAZEL_VERSION=6.2.0
ARG BAZEL_SHA256=f1e8f788637ac574d471d619d2096baaca04a19b57a034399e079633db441945
ARG BUILD_JOBS=4

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk
ENV CMAKE_C_COMPILER_LAUNCHER=ccache
ENV CMAKE_CXX_COMPILER_LAUNCHER=ccache

COPY docker/bazel-6.2.0.patch /bazel.patch
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=/root/.cache \
    --mount=type=secret,id=ca_bundle --mount=type=secret,id=proxy_ca \
    set -eu; \
    if [ -f /run/secrets/ca_bundle ]; then \
        export SSL_CERT_FILE=/run/secrets/ca_bundle; \
        export GIT_SSL_CAINFO=/run/secrets/ca_bundle; \
    fi; \
    apk add --no-cache \
        bash build-base linux-headers git curl unzip zip python3 \
        gcc=15.2.0-r5 g++=15.2.0-r5 cmake=4.2.3-r0 perl=5.42.2-r1 \
        openjdk11-jdk=11.0.32_p9-r0 autoconf automake libtool ninja lld patch \
        ccache zlib-dev openssl-dev libunwind-dev argp-standalone \
        musl-fts-dev musl-obstack-dev musl-libintl time; \
    curl --fail --location --retry 3 --silent --show-error \
        "https://github.com/bazelbuild/bazel/releases/download/${BAZEL_VERSION}/bazel-${BAZEL_VERSION}-dist.zip" \
        -o /tmp/bazel.zip; \
    printf '%s  %s\n' "$BAZEL_SHA256" /tmp/bazel.zip | sha256sum -c -; \
    mkdir /tmp/bazel-src; \
    unzip -q /tmp/bazel.zip -d /tmp/bazel-src; \
    cd /tmp/bazel-src; \
    patch -p1 < /bazel.patch; \
    if [ -f /run/secrets/proxy_ca ]; then \
        cp /etc/ssl/certs/java/cacerts /tmp/bazel-cacerts; \
        keytool -importcert -noprompt -alias build-network \
            -file /run/secrets/proxy_ca -keystore /tmp/bazel-cacerts -storepass changeit; \
        export JDK_JAVA_OPTIONS="-Djavax.net.ssl.trustStore=/tmp/bazel-cacerts -Djavax.net.ssl.trustStorePassword=changeit"; \
    fi; \
    export EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk --java_runtime_version=local_jdk --tool_java_runtime_version=local_jdk --host_copt=-D_LARGEFILE64_SOURCE --copt=-D_LARGEFILE64_SOURCE --jobs=${BUILD_JOBS} --local_ram_resources=10000 --color=no --curses=no"; \
    bash compile.sh; \
    install -m 0755 output/bazel /usr/local/bin/bazel; \
    cd /; \
    rm -rf /tmp/bazel-src /tmp/bazel.zip /bazel.patch /tmp/bazel-cacerts /root/.cache/bazel; \
    mkdir -p /src

WORKDIR /src
