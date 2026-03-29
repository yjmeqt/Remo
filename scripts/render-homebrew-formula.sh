#!/usr/bin/env bash
set -euo pipefail

VERSION=""
REPO=""
ARM64_SHA=""
X86_SHA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --arm64-sha)
      ARM64_SHA="$2"
      shift 2
      ;;
    --x86-sha)
      X86_SHA="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${REPO}" || -z "${ARM64_SHA}" || -z "${X86_SHA}" ]]; then
  echo "usage: $0 --version <version> --repo <owner/repo> --arm64-sha <sha> --x86-sha <sha>" >&2
  exit 1
fi

cat <<EOF
class Remo < Formula
  desc "Agent-first iOS remote control CLI"
  homepage "https://github.com/${REPO}"
  version "${VERSION}"
  license "MIT"

  on_arm do
    url "https://github.com/${REPO}/releases/download/v${VERSION}/remo-macos-arm64.tar.gz"
    sha256 "${ARM64_SHA}"
  end

  on_intel do
    url "https://github.com/${REPO}/releases/download/v${VERSION}/remo-macos-x86_64.tar.gz"
    sha256 "${X86_SHA}"
  end

  def install
    bin.install "remo"
  end

  test do
    system "#{bin}/remo", "--help"
  end
end
EOF
