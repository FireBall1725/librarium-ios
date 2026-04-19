#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
BINARY="$(mktemp /tmp/librarium-icon-gen-XXXXXX)"
trap 'rm -f "$BINARY"' EXIT
echo "⚙️  Compiling..."
swiftc generate-icon.swift -o "$BINARY"
echo "🎨 Generating icons..."
"$BINARY"
