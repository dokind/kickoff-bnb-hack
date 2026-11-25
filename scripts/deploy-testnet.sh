#!/usr/bin/env bash
# Deploys the two Cypher Run factories (StreakVaultFactory, CheckInLauncherFactory) to BNB Smart Chain
# testnet (chain 97) and prints the app commands with the deployed addresses filled in.
#
#   scripts/deploy-testnet.sh             deploy for real (asks before sending anything)
#   scripts/deploy-testnet.sh --yes       deploy for real without asking
#   scripts/deploy-testnet.sh --dry-run   simulate the deploy, send nothing, write nothing
#   scripts/deploy-testnet.sh --print     only print the app commands from the last deploy
#
# Needs: forge (https://getfoundry.sh) and contracts/.env with PRIVATE_KEY set to a throwaway
# testnet key that holds a little tBNB. The key is read by forge only; this script never prints it.
#
# Optional, to fill in the app commands (otherwise they are printed as <PLACEHOLDERS>):
#   ATTESTER_ADDRESS  address of the server's attester key (ATTESTER_PRIVATE_KEY in verifier/.env)
#   VERIFIER_URL      https address of the server's API, for phone builds (https://<site>/api)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
ENV_FILE="$CONTRACTS/.env"
# DEPLOYMENTS_FILE can be overridden to test --print against a sample file.
DEPLOYMENTS_FILE="${DEPLOYMENTS_FILE:-$CONTRACTS/deployments/bsc-testnet.json}"
PUBLIC_RPC="https://bsc-testnet-rpc.publicnode.com"

MODE="deploy"
ASSUME_YES="no"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --print) MODE="print" ;;
    --yes | -y) ASSUME_YES="yes" ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# True when NAME has a non-empty value in contracts/.env. Prints nothing.
env_file_has() {
  [ -f "$ENV_FILE" ] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?$1=[\"']?[^\"'[:space:]#]+" "$ENV_FILE"
}

# Reads one string or number value from the deployments JSON (flat object, one key per line or not).
json_value() {
  tr -d '\n' <"$DEPLOYMENTS_FILE" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([0-9a-zA-Z]*\)\"\{0,1\}.*/\1/p"
}

is_address() {
  [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]] && [[ ! "$1" =~ ^0x0{40}$ ]]
}

print_app_commands() {
  local launcher_factory="$1" vault_factory="$2"
  local attester_address="${ATTESTER_ADDRESS:-<YOUR_ATTESTER_ADDRESS>}"
  local verifier_url="${VERIFIER_URL:-<YOUR_VERIFIER_URL>}"
  # The web build calls the API on its own origin under /api, so it takes no VERIFIER_URL.
  local web_defines phone_defines
  web_defines="  --dart-define=CHECKIN_LAUNCHER_FACTORY=$launcher_factory \\
  --dart-define=STREAK_VAULT_FACTORY=$vault_factory \\
  --dart-define=ATTESTER_ADDRESS=$attester_address"
  phone_defines="$web_defines \\
  --dart-define=VERIFIER_URL=$verifier_url"

  cat <<EOF

App commands (run them in $ROOT/app)
------------------------------------------------------------------------------
# 1. Try the web app locally in Chrome, against a server on this computer (cd verifier && npm run dev)
flutter run -d chrome \\
$web_defines \\
  --dart-define=VERIFIER_URL=http://localhost:8787

# 2. Build the web app for hosting (upload the contents of app/build/web; the API is <site>/api)
flutter build web --release \\
$web_defines

# 3. Build the iPhone app (needs Xcode signing set up; install the .ipa on each phone)
flutter build ipa --release \\
$phone_defines
------------------------------------------------------------------------------
EOF

  if [[ "$attester_address$verifier_url" == *"<YOUR_"* ]]; then
    cat <<'EOF'
Values in <ANGLE BRACKETS> are yours to supply before running the commands:
  <YOUR_ATTESTER_ADDRESS>  the address of the server's attester key (the address of
                           ATTESTER_PRIVATE_KEY in verifier/.env). A round started from the app
                           names it as the address whose signature every check-in must carry. If
                           the app is built with another address, the server cannot sign for the
                           rounds it starts.
  <YOUR_VERIFIER_URL>      phone builds only: the server's API, for example https://<site>/api.
                           The web build needs none; it uses the address it is served from.
Or run this script again with them set, and it fills them in:
  ATTESTER_ADDRESS=0x... VERIFIER_URL=https://<site>/api scripts/deploy-testnet.sh --print
EOF
  fi
}

print_from_deployments() {
  [ -f "$DEPLOYMENTS_FILE" ] || fail "No deployment found at $DEPLOYMENTS_FILE. Deploy first (run this script without --print)."
  local chain_id launcher_factory vault_factory deployed_at
  chain_id="$(json_value chainId)"
  launcher_factory="$(json_value checkInLauncherFactory)"
  vault_factory="$(json_value streakVaultFactory)"
  deployed_at="$(json_value deployedAt)"
  [ "$chain_id" = "97" ] || fail "$DEPLOYMENTS_FILE is not a BNB testnet deployment (chainId: ${chain_id:-missing})."
  is_address "$launcher_factory" || fail "checkInLauncherFactory is missing or not an address in $DEPLOYMENTS_FILE."
  is_address "$vault_factory" || fail "streakVaultFactory is missing or not an address in $DEPLOYMENTS_FILE."

  echo
  echo "Deployment on BNB testnet (chain 97), from $DEPLOYMENTS_FILE"
  echo "  CheckInLauncherFactory: $launcher_factory"
  echo "  StreakVaultFactory:     $vault_factory"
  echo "  Deployed at block:      ${deployed_at:-unknown}"
  echo "  Explorer:               https://testnet.bscscan.com/address/$launcher_factory"
  print_app_commands "$launcher_factory" "$vault_factory"
}

if [ "$MODE" = "print" ]; then
  print_from_deployments
  exit 0
fi

# ── Checks ───────────────────────────────────────────────────────────────────
command -v forge >/dev/null 2>&1 || fail "forge is not installed. Install Foundry: https://getfoundry.sh"
[ -d "$CONTRACTS/lib/forge-std" ] || fail "Contract dependencies are missing. Run: (cd contracts && ./install-deps.sh)"
[ -f "$ENV_FILE" ] || fail "contracts/.env does not exist. Run: cp contracts/.env.example contracts/.env, then set PRIVATE_KEY in it."
env_file_has PRIVATE_KEY || fail "PRIVATE_KEY is empty in contracts/.env. Set it to a throwaway testnet key that holds a little tBNB."

if [ -z "${BSC_TESTNET_RPC_URL:-}" ] && ! env_file_has BSC_TESTNET_RPC_URL; then
  export BSC_TESTNET_RPC_URL="$PUBLIC_RPC"
  echo "BSC_TESTNET_RPC_URL is not set; using the public node $PUBLIC_RPC"
fi

cd "$CONTRACTS"

if [ "$MODE" = "dry-run" ]; then
  echo "Dry run: simulating the deploy on BNB testnet. Nothing is sent and nothing is written."
  forge script script/Deploy.s.sol --rpc-url bsc_testnet
  echo
  echo "Dry run finished. The addresses above are what a real deploy from this key would give"
  echo "as long as the key sends no other transaction first."
  if [ -f "$DEPLOYMENTS_FILE" ]; then
    echo "An earlier real deployment exists; its app commands follow."
    print_from_deployments
  else
    print_app_commands "<CHECKIN_LAUNCHER_FACTORY_FROM_DEPLOY>" "<STREAK_VAULT_FACTORY_FROM_DEPLOY>"
  fi
  exit 0
fi

# ── Real deploy ──────────────────────────────────────────────────────────────
if [ -f "$DEPLOYMENTS_FILE" ]; then
  echo "A deployment already exists at $DEPLOYMENTS_FILE."
  echo "Deploying again creates new factories; rounds opened with the old ones keep working"
  echo "but the app will be built against the new addresses."
fi
if [ "$ASSUME_YES" != "yes" ]; then
  echo "This sends 2 real transactions to BNB testnet (chain 97) from the key in contracts/.env."
  printf "Type deploy to continue: "
  read -r answer
  [ "$answer" = "deploy" ] || fail "Stopped. Nothing was sent."
fi

BACKUP=""
if [ -f "$DEPLOYMENTS_FILE" ]; then
  BACKUP="$DEPLOYMENTS_FILE.previous"
  cp "$DEPLOYMENTS_FILE" "$BACKUP"
fi

# --slow sends the two transactions one after the other: the factories name each other, so their
# order (and the deployer's nonce) must not change.
if ! forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast --slow --legacy --with-gas-price 1000000000; then
  # The script writes the deployments file before forge sends anything, so it may describe
  # contracts that were never deployed. Put back what was there before.
  if [ -n "$BACKUP" ]; then mv "$BACKUP" "$DEPLOYMENTS_FILE"; else rm -f "$DEPLOYMENTS_FILE"; fi
  fail "The deploy did not finish. The deployments file was put back as it was. Check the output above; if one transaction went through, deploy again (both factories are redeployed)."
fi

[ -f "$DEPLOYMENTS_FILE" ] || fail "forge finished but $DEPLOYMENTS_FILE was not written."

# Read-only check that both factories really have code on chain.
if command -v cast >/dev/null 2>&1; then
  for key in checkInLauncherFactory streakVaultFactory; do
    factory="$(json_value "$key")"
    code="$(cast code "$factory" --rpc-url bsc_testnet 2>/dev/null || true)"
    if [ -z "$code" ] || [ "$code" = "0x" ]; then
      fail "No contract code at $factory ($key) yet. Wait a few seconds and check it on https://testnet.bscscan.com/address/$factory before using the addresses."
    fi
    echo "Checked: $key has code on chain."
  done
fi

echo
echo "Deployed. The two deployment transaction hashes are in the forge output above and in"
echo "contracts/broadcast/Deploy.s.sol/97/run-latest.json. Save them for the submission."
print_from_deployments
