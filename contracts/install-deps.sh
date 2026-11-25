#!/bin/sh
# Fetches the four Solidity libraries into lib/ at the exact versions Flap's example repo pins.
# lib/ is git-ignored, so run this once after cloning.
set -e
cd "$(dirname "$0")"

fetch() { # name url tag commit
  if [ -d "lib/$1" ]; then echo "lib/$1 already present, skipping"; return; fi
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$3" "$2" "lib/$1"
  got=$(git -C "lib/$1" rev-parse HEAD)
  if [ "$got" != "$4" ]; then echo "lib/$1: expected commit $4, got $got" >&2; rm -rf "lib/$1"; exit 1; fi
  rm -rf "lib/$1/.git"
  echo "lib/$1 @ $3"
}

mkdir -p lib
fetch forge-std https://github.com/foundry-rs/forge-std v1.8.2 978ac6fadb62f5f0b723c996f64be52eddba6801
fetch openzeppelin-contracts https://github.com/OpenZeppelin/openzeppelin-contracts v4.9.6 dc44c9f1a4c3b10af99492eed84f83ed244203f6
fetch openzeppelin-contracts-upgradeable https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable v4.9.6 2d081f24cac1a867f6f73d512f2022e1fa987854
fetch solady https://github.com/vectorized/solady v0.1.26 acd959aa4bd04720d640bf4e6a5c71037510cc4b
