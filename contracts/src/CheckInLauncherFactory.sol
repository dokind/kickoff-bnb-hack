// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibClone} from "solady/utils/LibClone.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {LauncherFactoryBase} from "src/flap/LauncherFactoryBase.sol";
import {LauncherDataSchema, FieldDescriptor} from "src/flap/IVaultSchemas.sol";
import {CheckInLauncher, RoundConfig} from "./CheckInLauncher.sol";

/// @title CheckInLauncherFactory
/// @notice Launcher factory for `CheckInLauncher`, called by the Flap Portal in `Portal.newLauncher`. Every
///         Launcher it creates uses the same quote token and the paired `StreakVaultFactory`, both fixed
///         at construction.
///
///         `data` is `abi.encode(RoundConfig)`: one tuple
///         `(string name, string symbol, string meta, bytes32 salt, uint256 deposit, uint256 liquidityBps,
///           uint256 checkInGoal, uint256 deadline, address attester)`.
///
///         Upgrades: Flap's Guardian only, through the beacon. No owner, no other privileged function.
///
/// @dev Forked from Flap's `CrowdLauncherFactory` example.
contract CheckInLauncherFactory is LauncherFactoryBase {
    address public immutable hub;
    address public immutable guardian;
    address public immutable beacon;
    /// @notice The vault factory every Launcher of this factory uses.
    address public immutable pairedVaultFactory;
    /// @notice The ERC-20 every member pays the deposit in, and the pool's quote token.
    address public immutable quoteToken;

    /// @notice The longest a round may run, from creation to its deadline.
    uint256 public constant MAX_ROUND_DURATION = 90 days;
    /// @notice The liquidity part of the deposits the app proposes: 30%. Not enforced; a round may use
    ///         any value from 0 to 10000.
    uint256 public constant DEFAULT_LIQUIDITY_BPS = 3000;
    uint256 public constant MAX_BPS = 10_000;

    error ZeroAddress();
    error InvalidData();
    error EmptyField();
    error InvalidDeposit();
    error InvalidLiquidityBps(uint256 liquidityBps);
    error InvalidCheckInGoal();
    error InvalidDeadline(uint256 deadline);

    event CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt);
    event FlapLauncherImplementationUpgraded(address implementation);

    constructor(address hub_, address guardian_, address pairedVaultFactory_, address quoteToken_) {
        if (
            hub_ == address(0) || guardian_ == address(0) || pairedVaultFactory_ == address(0)
                || quoteToken_ == address(0)
        ) revert ZeroAddress();
        hub = hub_;
        guardian = guardian_;
        pairedVaultFactory = pairedVaultFactory_;
        quoteToken = quoteToken_;
        beacon = address(new UpgradeableBeacon(address(this), address(new CheckInLauncher())));
    }

    function _getHub() internal view override returns (address) {
        return hub;
    }

    function _getGuardian() internal view override returns (address) {
        return guardian;
    }

    function _newLauncher(address creator, bytes calldata data) internal override returns (address launcher) {
        // `abi.decode` ignores trailing bytes, so insist on the canonical encoding.
        RoundConfig memory c = abi.decode(data, (RoundConfig));
        if (keccak256(abi.encode(c)) != keccak256(data)) revert InvalidData();

        if (bytes(c.name).length == 0 || bytes(c.symbol).length == 0 || c.salt == bytes32(0)) revert EmptyField();
        if (c.attester == address(0)) revert ZeroAddress();
        if (c.deposit == 0) revert InvalidDeposit();
        if (c.liquidityBps > MAX_BPS) revert InvalidLiquidityBps(c.liquidityBps);
        if (c.checkInGoal == 0) revert InvalidCheckInGoal();
        if (c.deadline <= block.timestamp || c.deadline > block.timestamp + MAX_ROUND_DURATION) {
            revert InvalidDeadline(c.deadline);
        }

        launcher = LibClone.deployDeterministicERC1967BeaconProxy(beacon, c.salt);
        CheckInLauncher(launcher).initialize{value: msg.value}(hub, creator, quoteToken, pairedVaultFactory, c);
        emit CheckInLauncherCreated(launcher, creator, c.salt);
    }

    function upgradeVaultImplementation(address newImplementation) external override onlyGuardian {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        emit FlapLauncherImplementationUpgraded(newImplementation);
    }

    function beaconImplementation() external view returns (address) {
        return UpgradeableBeacon(beacon).implementation();
    }

    function launcherDataSchema() external pure override returns (LauncherDataSchema memory schema) {
        schema.description =
            "Check in to launch: each member pays the same deposit once and checks in on every day they move. Every check-in carries a signature from the attester (the app's server): check-ins are attested, not proven. When all check-ins together reach the goal before the deadline, anyone can launch the token through Flap. Sponsor money plus a fixed part of the deposits seeds the pool with half the supply; the rest of the deposits, the other half of the supply and 80% of the trading tax go to a StreakVault and are shared among members by the days each one checked in (20% of the tax is burned). Sponsors, the creator and the attester receive nothing. If the token has not launched by the deadline, deposits and sponsor money are refunded in full.";
        FieldDescriptor[] memory f = new FieldDescriptor[](9);
        f[0] = FieldDescriptor("name", "string", "Token name", 0);
        f[1] = FieldDescriptor("symbol", "string", "Token symbol", 0);
        f[2] = FieldDescriptor("meta", "string", "Metadata URI", 0);
        f[3] = FieldDescriptor("salt", "bytes32", "Vanity-mined launch salt", 0);
        f[4] = FieldDescriptor("deposit", "uint256", "Deposit every member pays once, in the quote token", 18);
        f[5] = FieldDescriptor(
            "liquidityBps", "uint256", "Part of the deposits that seeds the pool, in basis points (3000 = 30%)", 0
        );
        f[6] = FieldDescriptor("checkInGoal", "uint256", "Check-ins by all members together that open the launch", 0);
        f[7] = FieldDescriptor(
            "deadline", "time", "Last moment to join, check in and launch (within 90 days); refunds open after it", 0
        );
        f[8] = FieldDescriptor(
            "attester", "address", "Address whose signature every check-in needs (the app's server)", 0
        );
        schema.fields = f;
    }
}
