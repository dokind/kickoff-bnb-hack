// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibClone} from "solady/utils/LibClone.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {IPortal, IPortalTypes} from "src/flap/IPortal.sol";
import {DirectLaunchVaultFactoryBase} from "src/flap/DirectLaunchVaultFactoryBase.sol";
import {Distribution, DistributionTarget} from "src/flap/Distribution.sol";
import {VaultDataSchema, FieldDescriptor, FactoryPolicy} from "src/flap/IVaultSchemas.sol";
import {StreakVault, ICheckInLauncher} from "./StreakVault.sol";

/// @title StreakVaultFactory
/// @notice Vault factory paired with `CheckInLauncherFactory`. The Flap Portal calls `newVault` during a
///         launch; this factory only serves Launchers created by the paired Launcher factory.
///
///         What `newVault` checks before it deploys (rejected, never defaulted):
///           1. the caller is the Portal (`onlyHub`) and the common launch checks pass;
///           2. the launch caller is a Launcher the Portal recorded for `launcherFactory`;
///           3. `vaultData` is exactly `abi.encode(address launcher)` and names the calling Launcher;
///           4. the quote token is the Launcher's ERC-20 (not native), since the vault accounts in it;
///           5. the VAULT slot takes exactly 80% of the tax;
///           6. the reserved tokens are routed to this vault and are everything that is not in the pool;
///           7. the Launcher is mid-launch, so its check-ins are closed (the vault itself requires at least
///              one check-in).
///
/// @dev Forked from Flap's `CrowdVaultFactory` example.
contract StreakVaultFactory is DirectLaunchVaultFactoryBase {
    address public immutable beacon;
    /// @notice The only Launcher factory whose Launchers this vault factory accepts.
    address public immutable launcherFactory;

    uint16 public constant VAULT_SLOT_BPS = 8000;

    error NotFromLauncherFactory(address launcher);
    error VaultDataLauncherMismatch(address expected, address got);
    error QuoteTokenMismatch(address got, address expected);
    error VaultSlotBpsMismatch(uint16 got, uint16 expected);
    error WrongReserve(uint256 got, uint256 expected);
    error LauncherNotLaunching(address launcher);

    event FlapVaultImplementationUpgraded(address implementation);
    event StreakVaultCreated(address indexed vault, address indexed token, address indexed launcher);

    constructor(address launcherFactory_) {
        if (launcherFactory_ == address(0)) revert ZeroAddress();
        launcherFactory = launcherFactory_;
        beacon = address(new UpgradeableBeacon(address(this), address(new StreakVault())));
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function newVault(address token, address creator, uint8 launchKind, bytes calldata launchParams)
        external
        override
        onlyHub
        returns (address vault)
    {
        (IPortalTypes.CreateTaxTokenParams memory p, Distribution memory d, bytes memory vaultData) =
            _validateLaunch(token, creator, launchKind, launchParams);

        // 2. The caller must be a Launcher from the paired factory.
        if (IPortal(_getHub()).getLauncher(creator).launcherFactory != launcherFactory) {
            revert NotFromLauncherFactory(creator);
        }

        // 3. Exact vaultData, naming the calling Launcher.
        if (vaultData.length != 32) revert InvalidVaultData();
        address named = abi.decode(vaultData, (address));
        if (named != creator) revert VaultDataLauncherMismatch(creator, named);

        // 4. and 5. The quote token and the slot size the vault's accounting assumes.
        ICheckInLauncher l = ICheckInLauncher(creator);
        if (p.quoteToken != l.quoteToken()) revert QuoteTokenMismatch(p.quoteToken, l.quoteToken());
        uint16 slotBps = _vaultSlotBps(p.feeConfigs);
        if (slotBps != VAULT_SLOT_BPS) revert VaultSlotBpsMismatch(slotBps, VAULT_SLOT_BPS);

        // 6. The whole reserve comes to the vault.
        if (d.target != DistributionTarget.VAULT) {
            revert UnexpectedDistributionTarget(d.target, DistributionTarget.VAULT);
        }
        uint256 reserve = p.totalSupply - p.poolToken;
        if (reserve == 0 || d.amount != reserve) revert WrongReserve(d.amount, reserve);

        // 7. Mid-launch: check-ins are closed, so the shares the vault pays by are final.
        if (!l.launching()) revert LauncherNotLaunching(creator);

        vault = LibClone.deployDeterministicERC1967BeaconProxy(beacon, bytes32(uint256(uint160(token))));
        StreakVault(vault).initialize(token, creator, reserve);
        emit StreakVaultCreated(vault, token, creator);
    }

    /// @dev `_validateLaunch` already guarantees exactly one VAULT slot naming this factory.
    function _vaultSlotBps(IPortalTypes.FeeConfig[] memory fees) internal view returns (uint16) {
        for (uint256 i; i < fees.length; ++i) {
            if (fees[i].feeType != IPortalTypes.FeeSlotType.VAULT) continue;
            IPortalTypes.FeeConfigVault memory v = abi.decode(fees[i].configData, (IPortalTypes.FeeConfigVault));
            if (v.vaultFactory == address(this)) return fees[i].bps;
        }
        return 0;
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function vaultDataSchema() public pure override returns (VaultDataSchema memory schema) {
        schema.description =
            "Streak vault: holds the reserved tokens, the prize from the members' deposits and 80% of the trading tax, and pays members in proportion to the days each one checked in. Check-ins were signed by the round's attester. Set by the CheckInLauncher, not by hand.";
        schema.fields = new FieldDescriptor[](1);
        schema.fields[0] = FieldDescriptor("launcher", "address", "The CheckInLauncher that is launching", 0);
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    /// @dev ERC-20 quotes only. `newVault` additionally requires the Launcher's own quote token.
    function isQuoteTokenSupported(address quoteToken) public pure override returns (bool) {
        return quoteToken != address(0);
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function tokenCreationPolicies() public pure override returns (FactoryPolicy[] memory policies) {
        policies = new FactoryPolicy[](3);
        policies[0] = FactoryPolicy({
            target: "quoteToken",
            operator: "neq",
            value: abi.encode(address(0)),
            description: "ERC-20 quote only (the CheckInLauncher's quote token)."
        });
        policies[1] = FactoryPolicy({
            target: "vaultSlotBps",
            operator: "eq",
            value: abi.encode(uint256(VAULT_SLOT_BPS)),
            description: "The VAULT slot must take exactly 80% of the tax."
        });
        policies[2] = FactoryPolicy({
            target: "distribution.target",
            operator: "eq",
            value: abi.encode(uint8(DistributionTarget.VAULT)),
            description: "Everything outside the pool must be routed to this launch's vault."
        });
    }

    function upgradeVaultImplementation(address newImplementation) external override onlyGuardian {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        emit FlapVaultImplementationUpgraded(newImplementation);
    }

    function beaconImplementation() external view returns (address) {
        return UpgradeableBeacon(beacon).implementation();
    }
}
