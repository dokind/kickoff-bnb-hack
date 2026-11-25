// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IPortal} from "src/flap/IPortal.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {CheckInLauncherFactory} from "src/CheckInLauncherFactory.sol";
import {StreakVaultFactory} from "src/StreakVaultFactory.sol";

/// @notice Deploys the two factories on BNB Testnet (chain 97) and prints their addresses. With
///         `--broadcast` it also writes them to `deployments/bsc-testnet.json` for the app and the
///         verifier; a dry run writes nothing.
///
///   forge script script/Deploy.s.sol --rpc-url bsc_testnet                                    # dry run
///   forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast --slow --legacy \
///       --with-gas-price 1000000000                                                           # deploys
///
///   `--legacy --with-gas-price 1000000000` (1 gwei) is required on this testnet: fee estimation answers
///   1 wei there and such transactions are never mined. The gas limit of each transaction is set by forge
///   from its own simulation, not from the node's fee data.
///
///   Env: PRIVATE_KEY (deployer), BSC_TESTNET_RPC_URL, optional QUOTE_TOKEN (defaults to Flap's test USD).
///
/// @dev The factories name each other. The vault factory goes first with the Launcher factory's address
///      predicted from the deployer's next nonce, so the two deployments must be consecutive transactions.
contract Deploy is Script {
    address internal constant TEST_USD = 0x190C989D5665a0e404B444b53CAE9AbCfb600157;
    string internal constant DEPLOYMENTS_FILE = "deployments/bsc-testnet.json";

    function run() external {
        require(block.chainid == 97, "this script is for BNB Testnet (chain 97)");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address quoteToken = vm.envOr("QUOTE_TOKEN", TEST_USD);
        address hub = LaunchVaultAddresses.hub();
        address guardian = LaunchVaultAddresses.guardian();

        if (IPortal(hub).featureFlags() & 1 != 0) {
            console.log("WARNING: token creation is paused on this Portal. Flap must enable the Launcher factory.");
        }

        address predictedLauncherFactory = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

        vm.startBroadcast(pk);
        StreakVaultFactory vaultFactory = new StreakVaultFactory(predictedLauncherFactory);
        CheckInLauncherFactory launcherFactory =
            new CheckInLauncherFactory(hub, guardian, address(vaultFactory), quoteToken);
        vm.stopBroadcast();

        require(address(launcherFactory) == predictedLauncherFactory, "nonce moved: Launcher factory address mismatch");

        console.log("Deployer:               ", deployer);
        console.log("Portal (hub):           ", hub);
        console.log("Quote token:            ", quoteToken);
        console.log("StreakVaultFactory:     ", address(vaultFactory));
        console.log("CheckInLauncherFactory: ", address(launcherFactory));
        console.log("Salt lock fee (wei):    ", vm.toString(IPortal(hub).SALT_LOCK_FEE()));
        console.log("Block:                  ", vm.toString(block.number));

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _writeDeployment(hub, address(launcherFactory), address(vaultFactory), quoteToken);
            console.log("Wrote", DEPLOYMENTS_FILE);
        } else {
            console.log("Dry run: nothing sent,", DEPLOYMENTS_FILE, "not written.");
        }
    }

    /// @dev `deployedAt` is the chain's block when the script ran, just before the two transactions are
    ///      mined: a safe block to start reading the factories' events from. The file is written before
    ///      forge sends the transactions, so check that the broadcast itself succeeded.
    function _writeDeployment(address hub, address launcherFactory, address vaultFactory, address quoteToken) private {
        string memory o = "deployment";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeAddress(o, "portal", hub);
        vm.serializeAddress(o, "checkInLauncherFactory", launcherFactory);
        vm.serializeAddress(o, "streakVaultFactory", vaultFactory);
        vm.serializeAddress(o, "quoteToken", quoteToken);
        string memory json = vm.serializeUint(o, "deployedAt", block.number);
        vm.createDir("deployments", true);
        vm.writeJson(json, DEPLOYMENTS_FILE);
    }
}
