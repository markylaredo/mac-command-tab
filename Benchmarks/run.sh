#!/bin/bash
# Build and run the offline window-search benchmark.
#
# This compiles the application's real search implementation directly from the
# app target's sources. Nothing is copied, so the benchmark cannot silently drift
# away from shipped behaviour. The app target itself is not modified.
#
# No network access, no API key, no screen recording or accessibility permission
# required: the fixture windows never touch the running accessibility server.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/.build/benchmark"

mkdir -p "$OUT" "$ROOT/.build/bmcache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/bmcache"

# The application sources under test, plus the harness.
SOURCES=(
    MacCommandTab/Windows/WindowInfo.swift
    MacCommandTab/Switcher/WindowSearch.swift
    Benchmarks/WindowSearchFixtures.swift
    Benchmarks/WindowSearchQueries.swift
    Benchmarks/main.swift
)

swiftc \
    -O \
    -swift-version 6 \
    -target arm64-apple-macos14.0 \
    -framework AppKit \
    -framework ApplicationServices \
    "${SOURCES[@]}" \
    -o "$OUT/window-search-benchmark"

"$OUT/window-search-benchmark"
