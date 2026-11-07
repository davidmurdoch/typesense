#!/usr/bin/env python3
"""Compare the published Alpine runtime with a shared-library candidate on one host."""
import concurrent.futures
import hashlib
import http.client
import json
from pathlib import Path
import statistics
import subprocess
import sys
import tarfile
import time
import urllib.parse
import urllib.request
import uuid

RELEASE = "https://github.com/davidmurdoch/typesense/releases/download/v30.2-alpine.3/"
BASELINE_SHA = "3bc1e6c02b588ad36d902563328ffd78f73de9b6a357de851a1bb77ff89e2ed8"
KEY = "synthetic-shared-library-benchmark"
QUERIES = ["chicken", "chiken", "rice", "brown rice", "oat", "yogurt", "cafe", "jalapeno"]
LOCALES = {
    "en": ("Café latte", "cafe"),
    "de": ("Frühstück Müsli", "müsli"),
    "fr": ("Crème brûlée", "crème"),
    "ru": ("Куриная грудка", "куриная"),
    "zh": ("鸡肉炒饭", "炒饭"),
    "ja": ("鶏肉カレー", "カレー"),
    "ko": ("닭고기 볶음밥", "볶음밥"),
    "th": ("ข้าวผัดไก่", "ไก่"),
    "fa": ("برنج مرغ", "مرغ"),
}


def command(*args):
    return subprocess.check_output(args, text=True, timeout=120).strip()


def download(url, path):
    with urllib.request.urlopen(url, timeout=90) as response, path.open("wb") as out:
        while chunk := response.read(1024 * 1024):
            out.write(chunk)


def package_size(path):
    with tarfile.open(path, "r:gz", ignore_zeros=True) as archive:
        metadata = archive.extractfile(".PKGINFO").read().decode()
    return int(next(line.split(" = ", 1)[1] for line in metadata.splitlines()
                    if line.startswith("size = ")))


def audit(binary, image):
    needed = command("readelf", "-dW", str(binary))
    required = ["libssl.so.3", "libcrypto.so.3", "libcurl.so.4", "libz.so.1",
                "libstdc++.so.6", "libicuuc.so.78", "libicui18n.so.78"]
    missing = [name for name in required if "[" + name + "]" not in needed]
    loaded = command("docker", "run", "--rm", "--entrypoint",
                     "/lib/ld-musl-x86_64.so.1", image, "--list", "/opt/typesense-server")
    if "libgcc_s.so.1" not in loaded:
        missing.append("libgcc_s.so.1 (transitive runtime)")
    # Check public library definitions; libarchive has unrelated private crc32 functions.
    symbols = command("nm", "--defined-only", "--extern-only", str(binary))
    anchors = {"inflate", "deflate", "crc32", "SSL_new", "OPENSSL_init_crypto",
               "curl_easy_init", "__cxa_throw", "_ZSt20__throw_length_errorPKc"}
    embedded = [line.split()[-1] for line in symbols.splitlines() if line.split()
                and (line.split()[-1] in anchors or "icu_71" in line.split()[-1]
                     or "icudt71" in line.split()[-1])]
    if missing or embedded:
        raise RuntimeError("Shared linkage incomplete: " + json.dumps(
            {"missing": missing, "embedded": embedded[:20]}))
    return {"needed": required, "old_library_anchor_definitions": embedded}


class Client:
    def __init__(self, port):
        self.connection = http.client.HTTPConnection("127.0.0.1", port, timeout=15)

    def request(self, path, method="GET", value=None, raw=None):
        body = raw if raw is not None else json.dumps(value).encode() if value is not None else None
        self.connection.request(method, path, body, {
            "X-TYPESENSE-API-KEY": KEY, "Content-Type": "application/json"})
        response = self.connection.getresponse()
        data = response.read()
        if response.status not in (200, 201):
            raise RuntimeError("HTTP " + str(response.status) + " for " + path)
        return data

    def search(self, collection, query):
        params = urllib.parse.urlencode({"q": query, "query_by": "name",
                                         "per_page": 5, "include_fields": "id"})
        result = json.loads(self.request("/collections/" + collection + "/documents/search?" + params))
        return {"found": result["found"], "ids": [hit["document"]["id"] for hit in result["hits"]]}

    def close(self):
        self.connection.close()


def start(image, name, volume):
    started = time.perf_counter()
    command("docker", "run", "-d", "--name", name, "--cpus=1", "--memory=256m",
            "--memory-swap=256m", "-p", "127.0.0.1::8108",
            "-v", volume + ":/var/lib/typesense", image,
            "--data-dir=/var/lib/typesense", "--api-key=" + KEY)
    port = int(command("docker", "port", name, "8108/tcp").rsplit(":", 1)[1])
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        client = Client(port)
        try:
            if json.loads(client.request("/health"))["ok"]:
                client.close()
                return port, time.perf_counter() - started
        except (OSError, http.client.HTTPException, RuntimeError):
            pass
        finally:
            client.close()
        time.sleep(0.1)
    raise RuntimeError("Runtime did not become healthy: " + name)


def stop(name):
    subprocess.run(["docker", "stop", "-t", "20", name], check=True,
                   stdout=subprocess.DEVNULL, timeout=30)
    subprocess.run(["docker", "rm", name], check=True, stdout=subprocess.DEVNULL, timeout=15)


def create_collection(client, name, locale, documents):
    client.request("/collections", "POST", {"name": name, "fields": [
        {"name": "name", "type": "string", "locale": locale},
        {"name": "boost", "type": "int32"}], "default_sorting_field": "boost"})
    data = "\n".join(json.dumps(doc, ensure_ascii=False) for doc in documents).encode()
    results = client.request("/collections/" + name + "/documents/import?action=create", "POST", raw=data)
    if not all(json.loads(line)["success"] for line in results.splitlines()):
        raise RuntimeError("Fixture import failed")


def fixtures(client):
    words = ["Chicken breast", "Brown rice", "Rolled oats", "Greek yogurt",
             "Café latte", "Jalapeño pepper", "Chicken rice bowl", "Oat milk"]
    docs = [{"id": str(i), "name": words[i % len(words)] + " brand " + str(i % 97),
             "boost": i} for i in range(5000)]
    create_collection(client, "foods", "en", docs)
    for locale, (text, _) in LOCALES.items():
        create_collection(client, "locale_" + locale, locale, [
            {"id": "match", "name": text, "boost": 2},
            {"id": "other", "name": "plain water", "boost": 1}])


def signature(client):
    return {"foods": [client.search("foods", query) for query in QUERIES],
            "locales": {locale: client.search("locale_" + locale, query)
                        for locale, (_, query) in LOCALES.items()}}


def memory(name):
    text = command("docker", "exec", name, "cat", "/proc/1/smaps_rollup")
    return {line.split(":")[0] + "_KiB": int(line.split()[1]) for line in text.splitlines()
            if line.startswith(("Rss:", "Pss:", "Private_Dirty:"))}


def measure(image, name, volume):
    port, startup = start(image, name, volume)
    client = Client(port)
    try:
        began = time.perf_counter()
        fixtures(client)
        imported = time.perf_counter() - began
        expected = signature(client)
        for i in range(80):
            client.search("foods", QUERIES[i % len(QUERIES)])
        latencies = []
        for i in range(800):
            began = time.perf_counter_ns()
            client.search("foods", QUERIES[i % len(QUERIES)])
            latencies.append((time.perf_counter_ns() - began) / 1_000_000)

        def worker(offset):
            connection = Client(port)
            try:
                for i in range(300):
                    connection.search("foods", QUERIES[(i + offset) % len(QUERIES)])
            finally:
                connection.close()

        began = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(worker, range(4)))
        throughput = 1200 / (time.perf_counter() - began)
        return {"process_start_s": startup, "import_s": imported,
                "warm_search_p50_ms": statistics.median(latencies),
                "warm_search_p95_ms": statistics.quantiles(latencies, n=100)[94],
                "concurrency_4_qps": throughput, "memory": memory(name),
                "signature": expected}
    finally:
        client.close()
        stop(name)


def main():
    image, destination, candidate_apk = sys.argv[1:]
    root = Path(destination).resolve()
    root.mkdir(parents=True, exist_ok=True)
    baseline = root / "baseline"
    baseline.mkdir()
    archive = baseline / "runtime.tar.gz"
    download(RELEASE + "typesense-server-30.2-alpine.3-linux-musl-amd64.tar.gz", archive)
    with tarfile.open(archive, "r:gz") as source:
        binary = source.extractfile("typesense-server").read()
    if hashlib.sha256(binary).hexdigest() != BASELINE_SHA:
        raise RuntimeError("Published baseline executable mismatch")
    (baseline / "typesense-server").write_bytes(binary)
    (baseline / "typesense-server").chmod(0o755)
    (baseline / "Dockerfile").write_text("FROM " + image +
        "\nCOPY typesense-server /opt/typesense-server\n")
    prefix = "typesense-shared-" + uuid.uuid4().hex[:10]
    baseline_image = prefix + ":baseline"
    command("docker", "build", "-q", "-t", baseline_image, str(baseline))
    report = {"limits": {"cpus": 1, "memory_MiB": 256, "food_documents": 5000},
              "startup_definition": "process start to HTTP health, including Docker launch; OS file caches are not flushed",
              "linkage": audit(Path("dist/typesense-server"), image),
              "runtime_packages": command("docker", "run", "--rm", "--entrypoint", "apk", image,
                  "info", "-v", "libcrypto3", "libssl3", "libcurl", "zlib",
                  "libstdc++", "libgcc", "icu-libs", "icu-data-full").splitlines(),
              "runs": []}
    volumes, names = [], []
    try:
        for index, label in enumerate(["baseline", "candidate", "candidate", "baseline"]):
            name = prefix + "-" + str(index)
            volume = name + "-data"
            names.append(name)
            volumes.append(volume)
            command("docker", "volume", "create", volume)
            result = measure(baseline_image if label == "baseline" else image, name, volume)
            report["runs"].append({"build": label, **result})
            print(label + " " + json.dumps({k: v for k, v in result.items() if k != "signature"}), flush=True)
        expected = report["runs"][0]["signature"]
        report["behavior_equal"] = all(run["signature"] == expected for run in report["runs"])
        # The last volume was written by the baseline; reopen it with the candidate.
        name = prefix + "-reopen"
        names.append(name)
        port, restart = start(image, name, volumes[-1])
        client = Client(port)
        try:
            report["baseline_data_reopen"] = {"startup_s": restart,
                                              "behavior_equal": signature(client) == expected}
        finally:
            client.close()
            stop(name)
        baseline_apk = root / "baseline.apk"
        download(RELEASE + "typesense-30.2-r3.apk", baseline_apk)
        data_packages = {}
        for kind in ["en", "full"]:
            path = root / ("icu-data-" + kind + ".apk")
            download("https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/icu-data-"
                     + kind + "-78.1-r0.apk", path)
            data_packages[kind] = {"installed_bytes": package_size(path),
                                   "apk_bytes": path.stat().st_size}
        report["sizes"] = {"baseline_executable_bytes": len(binary),
                          "candidate_executable_bytes": Path("dist/typesense-server").stat().st_size,
                          "baseline_apk_bytes": baseline_apk.stat().st_size,
                          "candidate_apk_bytes": Path(candidate_apk).stat().st_size,
                          "icu_data": data_packages}
        size = report["sizes"]
        report["net_installed_and_retained_package_delta_bytes"] = (
            size["candidate_executable_bytes"] - size["baseline_executable_bytes"]
            + size["candidate_apk_bytes"] - size["baseline_apk_bytes"]
            + data_packages["full"]["installed_bytes"] - data_packages["en"]["installed_bytes"]
            + data_packages["full"]["apk_bytes"] - data_packages["en"]["apk_bytes"])
        if not report["behavior_equal"] or not report["baseline_data_reopen"]["behavior_equal"]:
            raise RuntimeError("Baseline/candidate search behavior differs; inspect signatures")
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (root / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        for name in names:
            subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        for volume in volumes:
            subprocess.run(["docker", "volume", "rm", volume], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        subprocess.run(["docker", "image", "rm", baseline_image], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=30)
    print(json.dumps({k: v for k, v in report.items() if k != "runs"}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    if sys.argv[1] == "--audit":
        print(json.dumps(audit(Path(sys.argv[3]), sys.argv[2])))
    else:
        main()
