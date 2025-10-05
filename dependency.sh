#!/bin/bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script with sudo or as root." >&2
  exit 1
fi

TOOLS=(aws jq yq nc mysql)

PKG_MANAGER=""
PKG_UPDATE=""
PKG_INSTALL=""
declare -A PKG_MAP

if command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"
  PKG_UPDATE="dnf makecache -y"
  PKG_INSTALL="dnf install -y"
  PKG_MAP=(
    [aws]="awscli"
    [jq]="jq"
    [yq]="yq"
    [nc]="nmap-ncat"
    [mysql]="mysql"
  )
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER="yum"
  PKG_UPDATE="yum makecache -y"
  PKG_INSTALL="yum install -y"
  PKG_MAP=(
    [aws]="awscli"
    [jq]="jq"
    [yq]="yq"
    [nc]="nmap-ncat"
    [mysql]="mysql"
  )
elif command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER="apt"
  PKG_UPDATE="apt-get update -y"
  PKG_INSTALL="apt-get install -y"
  PKG_MAP=(
    [aws]="awscli"
    [jq]="jq"
    [yq]="yq"
    [nc]="netcat-openbsd"
    [mysql]="mysql-client"
  )
elif command -v zypper >/dev/null 2>&1; then
  PKG_MANAGER="zypper"
  PKG_UPDATE="zypper refresh"
  PKG_INSTALL="zypper install -y"
  PKG_MAP=(
    [aws]="aws-cli"
    [jq]="jq"
    [yq]="yq"
    [nc]="netcat"
    [mysql]="mysql-client"
  )
elif command -v apk >/dev/null 2>&1; then
  PKG_MANAGER="apk"
  PKG_UPDATE="apk update"
  PKG_INSTALL="apk add --no-cache"
  PKG_MAP=(
    [aws]="aws-cli"
    [jq]="jq"
    [yq]="yq"
    [nc]="netcat-openbsd"
    [mysql]="mysql-client"
  )
elif command -v brew >/dev/null 2>&1; then
  PKG_MANAGER="brew"
  PKG_UPDATE="brew update"
  PKG_INSTALL="brew install"
  PKG_MAP=(
    [aws]="awscli"
    [jq]="jq"
    [yq]="yq"
    [nc]="netcat"
    [mysql]="mysql"
  )
else
  echo "Unsupported package manager. Install awscli, jq, yq, nc, and mysql manually." >&2
  exit 1
fi

packages_to_install=()
missing_tools=()
for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    pkg_name="${PKG_MAP[$tool]:-}"
    if [[ -n "$pkg_name" ]]; then
      packages_to_install+=("$pkg_name")
    else
      missing_tools+=("$tool")
    fi
  fi
done

if [[ ${#packages_to_install[@]} -gt 0 ]]; then
  declare -A seen
  unique_packages=()
  for pkg in "${packages_to_install[@]}"; do
    if [[ -z ${seen[$pkg]+x} ]]; then
      unique_packages+=("$pkg")
      seen[$pkg]=1
    fi
  done

  echo "Using $PKG_MANAGER to install: ${unique_packages[*]}"
  eval "$PKG_UPDATE"
  eval "$PKG_INSTALL ${unique_packages[*]}"
else
  echo "All target tools already present."
fi

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "No package mapping for: ${missing_tools[*]}. Please install manually." >&2
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "Attempting manual yq install..."
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      echo "Unsupported architecture for yq binary: $ARCH" >&2
      exit 1
      ;;
  esac
  YQ_URL="https://github.com/mikefarah/yq/releases/latest/download/yq_${OS}_${ARCH}"
  curl -fsSL "$YQ_URL" -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "yq installation failed." >&2
  exit 1
fi

tools_missing_after=()
for tool in "${TOOLS[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    tools_missing_after+=("$tool")
  fi
done

if [[ ${#tools_missing_after[@]} -gt 0 ]]; then
  echo "The following tools are still missing: ${tools_missing_after[*]}" >&2
  exit 1
fi

echo "All dependencies installed and available."
