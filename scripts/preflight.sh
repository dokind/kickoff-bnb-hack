#!/usr/bin/env bash
# Read-only check to run right before a live demo. It sends no transaction, reads no key and no
# .env file; it only makes eth_calls on BSC testnet and GET requests to the live API.
#
#   scripts/preflight.sh
#
# It checks:
#   1. OriginRegistry.origin() gives a host, and that host's /api/health answers with
#      host == onChain and no setOrigin pending (the apps find the API through the registry).
#   2. The Flap Portal still accepts the CheckInLauncherFactory: launcherFactoryMultiplier = (true, 10000).
#   3. How many more wallets the faucet can fund: (balance - 0.05 reserve) / drip, also capped by
#      the faucet's total limit. Uses GET /api/faucet when the server has it, otherwise the faucet
#      wallet's balance and FAUCET_DRIP_BNB (default 0.012, the live setting).
#   4. The judges' round and the Demo Day round: members, check-ins against the goal, pool, launched,
#      and how many check-ins are still missing.
#
# Needs: cast (https://getfoundry.sh), curl, jq. Exit code 1 if a check fails, 0 otherwise
# (a warning, such as a low faucet, does not fail).
#
# Optional: RPC_URL, FAUCET_DRIP_BNB, MIN_WALLETS (warn below this many faucet wallets, default 40),
# ROUNDS (space-separated "label=address" pairs to report instead of the default two).
set -uo pipefail

RPC_URL="${RPC_URL:-https://bsc-testnet-rpc.publicnode.com}"
PORTAL=0x000042108465206185A077Edc3F3fd2b49060000
FACTORY=0x2A872200B83dD025977d785cDE05356d23eA4153
REGISTRY=0xb9aD45Dc177C801f10670F2aac03B467f1C367d2
FAUCET=0xaC33dE0fe7C7a2e779A9Ba9C116C1fFe0aCd19f8
FAUCET_DRIP_BNB="${FAUCET_DRIP_BNB:-0.012}"
MIN_WALLETS="${MIN_WALLETS:-40}"
ROUNDS="${ROUNDS:-Bangkok-Demo-Run=0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876 Demo-Day=0x378d729aE7122e5Cf7d6f4ed8797710d2503EDb5}"
RESERVE_WEI=50000000000000000

for tool in cast curl jq; do
  command -v "$tool" >/dev/null || { echo "preflight: $tool is not installed" >&2; exit 1; }
done

failed=0
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; failed=1; }
call() { cast call --rpc-url "$RPC_URL" "$@" 2>/dev/null; }
# cast prints big numbers as "1530000000000000000000 [1.53e21]"; keep the first field.
num()  { call "$@" | awk 'NR==1{print $1}'; }
# Whole units (18 decimals) of a wei amount, rounded down.
units() { local v="${1:-0}"; [ "${#v}" -le 18 ] && echo 0 || echo "${v:0:${#v}-18}"; }

echo "API"
host="$(call "$REGISTRY" 'origin()(string)' | tr -d '"')"
if [ -z "$host" ]; then
  bad "could not read origin() from OriginRegistry $REGISTRY"
  api=""
else
  api="https://$host/api"
  health="$(curl -fsS --max-time 10 "$api/health" 2>/dev/null)"
  if [ -z "$health" ]; then
    bad "$api/health did not answer (tunnel down, or the host just changed: try again in a minute)"
  else
    h_host="$(jq -r '.origin.host // empty' <<<"$health")"
    h_chain="$(jq -r '.origin.onChain // empty' <<<"$health")"
    h_pending="$(jq -r '.origin.pending // false' <<<"$health")"
    if [ "$h_host" = "$host" ] && [ "$h_chain" = "$host" ] && [ "$h_pending" = "false" ]; then
      ok "$api answers; registry, server and tunnel agree on $host"
    else
      bad "host mismatch: registry $host, server host '$h_host', server onChain '$h_chain', pending $h_pending"
    fi
  fi
fi

echo "Flap Portal"
mult="$(call "$PORTAL" 'launcherFactoryMultiplier(address)(bool,uint16)' "$FACTORY" | awk '{printf "%s ", $1}')"
if [ "$mult" = "true 10000 " ]; then ok "factory $FACTORY is accepted (true, 10000)"; else bad "launcherFactoryMultiplier = '$mult', expected 'true 10000'"; fi

echo "Faucet"
status=""
[ -n "${api:-}" ] && status="$(curl -fsS --max-time 10 "$api/faucet" 2>/dev/null)"
if [ -n "$status" ] && jq -e 'has("walletsLeft")' >/dev/null 2>&1 <<<"$status"; then
  left="$(jq -r '.walletsLeft // "unknown"' <<<"$status")"
  enabled="$(jq -r '.enabled' <<<"$status")"
  bal="$(jq -r '.balance // "0"' <<<"$status")"
  detail="from the server: balance $(cast from-wei "$bal" 2>/dev/null) test BNB, drip $(cast from-wei "$(jq -r .dripWei <<<"$status")"), $(jq -r .perIpPerHour <<<"$status") per network an hour, $(jq -r .funded <<<"$status") funded so far"
  [ "$enabled" = "true" ] || bad "the faucet is off on the server"
else
  bal="$(cast balance --rpc-url "$RPC_URL" "$FAUCET" 2>/dev/null)"
  drip="$(cast to-wei "$FAUCET_DRIP_BNB" 2>/dev/null)"
  if [ -z "$bal" ] || [ -z "$drip" ]; then
    left="unknown"; detail="could not read the faucet balance"
  elif [ "$(echo "$bal < $drip + $RESERVE_WEI" | bc)" = "1" ]; then
    left=0; detail="balance $(cast from-wei "$bal") test BNB"
  else
    left="$(echo "($bal - $RESERVE_WEI) / $drip" | bc)"
    detail="balance $(cast from-wei "$bal") test BNB at $FAUCET_DRIP_BNB a wallet (server has no GET /faucet yet)"
  fi
fi
if [ "$left" = "unknown" ]; then bad "faucet: $detail"
elif [ "$left" -lt "$MIN_WALLETS" ]; then warn "faucet can fund about $left more wallets (want $MIN_WALLETS): $detail"
else ok "faucet can fund about $left more wallets: $detail"; fi

for pair in $ROUNDS; do
  label="${pair%%=*}"; launcher="${pair#*=}"
  echo "Round ${label//-/ } ($launcher)"
  members="$(num "$launcher" 'memberCount()(uint256)')"
  checks="$(num "$launcher" 'totalCheckIns()(uint256)')"
  goal="$(num "$launcher" 'checkInGoal()(uint256)')"
  launched="$(call "$launcher" 'launched()(bool)')"
  can="$(call "$launcher" 'canLaunch()(bool)')"
  pool="$(num "$launcher" 'poolQuoteNow()(uint256)')"
  deadline="$(num "$launcher" 'deadline()(uint256)')"
  if [ -z "$members" ] || [ -z "$goal" ]; then bad "could not read the round"; continue; fi
  when="$(date -u -r "$deadline" '+%a %d %b %H:%M UTC' 2>/dev/null || date -u -d "@$deadline" '+%a %d %b %H:%M UTC' 2>/dev/null)"
  line="$members members, $checks of $goal check-ins, pool $(units "$pool") test USD, deadline $when"
  if [ "$launched" = "true" ]; then ok "launched; $line"
  elif [ "$can" = "true" ]; then ok "ready to launch now; $line"
  else
    togo=$((goal - checks)); [ "$togo" = "1" ] && unit="check-in" || unit="check-ins"
    ok "open, $togo $unit to go (each wallet once per UTC day); $line"
  fi
done

echo
if [ "$failed" = "0" ]; then echo "preflight: all checks passed"; else echo "preflight: some checks FAILED"; fi
exit "$failed"
