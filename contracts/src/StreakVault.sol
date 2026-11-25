// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";
import {DirectLaunchVaultBase} from "src/flap/DirectLaunchVaultBase.sol";
import {IStrategy} from "src/flap/IStrategy.sol";
import {VaultUISchema, VaultMethodSchema, FieldDescriptor} from "src/flap/IVaultSchemas.sol";
import {PRODUCT_NAME} from "./Product.sol";

/// @notice The slice of `CheckInLauncher` the vault and its factory read.
interface ICheckInLauncher {
    function quoteToken() external view returns (address);
    function attester() external view returns (address);
    function totalCheckIns() external view returns (uint256);
    function daysOf(address member) external view returns (uint256);
    function launching() external view returns (bool);
}

/// @title StreakVault
/// @notice Holds what a round's members share after the launch:
///           - the reserved half of the token supply, handed over by the Portal at launch;
///           - the prize: the part of the members' deposits that did not go to the pool, sent by the
///             Launcher in the launch transaction;
///           - the vault's share of the trading tax (80%), which arrives in the quote token while the
///             token trades.
///
///         A member with `d = daysOf(member)` of the `totalCheckIns` counted at launch can claim:
///
///           tokens:  reservedTokens  * d / totalCheckIns                       (once)
///           quote:   quoteReceived() * d / totalCheckIns − already paid to them (again as tax arrives)
///
///         Members with no check-in receive nothing. There is no settlement step, no list to post and
///         no privileged role: the shares are fixed by the check-ins the Launcher recorded, which are
///         closed from the moment of the launch.
///
///         Nobody can withdraw from this contract except through `claim()`: not the attester, a
///         sponsor, the creator or the deployer. The attester's only influence was signing the daily
///         check-ins before the launch; check-ins are attested, not proven.
///
/// @dev Forked from Flap's `CrowdVault` example. Deployed per launch as a beacon proxy by `StreakVaultFactory`.
contract StreakVault is DirectLaunchVaultBase, Initializable, IStrategy {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /// @notice The launched token.
    address public taxToken;
    address public quoteToken;
    address public launcher;
    /// @notice All check-ins of the round, fixed at launch. The denominator of every share.
    uint256 public totalCheckIns;
    /// @notice Tokens reserved for the members.
    uint256 public reservedTokens;
    bool public reserveReceived;

    /// @notice Quote token paid out so far.
    uint256 public totalQuotePaid;
    /// @notice Tokens paid out so far.
    uint256 public totalTokensPaid;
    /// @notice Tokens `member` has claimed. Zero until their first claim.
    mapping(address member => uint256 amount) public claimedTokens;
    /// @notice Quote token `member` has claimed so far.
    mapping(address member => uint256 amount) public claimedQuote;

    event Claimed(address indexed member, uint256 tokenAmount, uint256 quoteAmount);

    error ZeroAddress();
    error NoCheckIns();
    error InvalidDistribution();
    error NothingToClaim();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Called once by the factory in `newVault`, in the same transaction that deploys the proxy. The
    ///      factory has already checked that `launcher_` is a CheckInLauncher in the middle of its launch,
    ///      so check-ins are closed and `totalCheckIns` can no longer change.
    function initialize(address taxToken_, address launcher_, uint256 reservedTokens_) external initializer {
        if (taxToken_ == address(0) || launcher_ == address(0)) revert ZeroAddress();
        ICheckInLauncher l = ICheckInLauncher(launcher_);
        uint256 total = l.totalCheckIns();
        if (total == 0) revert NoCheckIns();

        taxToken = taxToken_;
        launcher = launcher_;
        quoteToken = l.quoteToken();
        totalCheckIns = total;
        reservedTokens = reservedTokens_;
        if (quoteToken == address(0)) revert ZeroAddress();
    }

    /// @inheritdoc IStrategy
    /// @dev The Portal hands over the reserved half of the supply here, once, during the launch.
    function initializeDistribution(address token, uint256 amount, bytes calldata, bytes32) external override onlyHub {
        if (reserveReceived || token != taxToken || amount != reservedTokens) revert InvalidDistribution();
        reserveReceived = true;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit FlapDistributionInitialized(token, amount);
    }

    function version() external pure returns (string memory) {
        return "v1.0.0";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Claims
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Days `member` checked in, as recorded by the Launcher. Fixed since the launch.
    function daysOf(address member) public view returns (uint256) {
        return ICheckInLauncher(launcher).daysOf(member);
    }

    /// @notice All quote token this vault has ever received: the prize plus the trading tax so far.
    function quoteReceived() public view returns (uint256) {
        return IERC20(quoteToken).balanceOf(address(this)) + totalQuotePaid;
    }

    /// @notice What `member` would receive from `claim()` right now. Zero for anyone with no check-in.
    function claimable(address member) public view returns (uint256 tokenAmount, uint256 quoteAmount) {
        uint256 d = daysOf(member);
        if (d == 0) return (0, 0);
        if (claimedTokens[member] == 0) tokenAmount = (reservedTokens * d) / totalCheckIns;
        quoteAmount = (quoteReceived() * d) / totalCheckIns - claimedQuote[member];
    }

    /// @notice Claim the caller's share. The first call pays the tokens and the caller's share of the
    ///         quote received so far; later calls pay the share of the tax that arrived since.
    function claim() external {
        (uint256 tokenAmount, uint256 quoteAmount) = claimable(msg.sender);
        if (tokenAmount == 0 && quoteAmount == 0) revert NothingToClaim();

        if (tokenAmount != 0) {
            claimedTokens[msg.sender] = tokenAmount;
            totalTokensPaid += tokenAmount;
        }
        if (quoteAmount != 0) {
            claimedQuote[msg.sender] += quoteAmount;
            totalQuotePaid += quoteAmount;
        }
        if (tokenAmount != 0) IERC20(taxToken).safeTransfer(msg.sender, tokenAmount);
        if (quoteAmount != 0) IERC20(quoteToken).safeTransfer(msg.sender, quoteAmount);
        emit Claimed(msg.sender, tokenAmount, quoteAmount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IDirectLaunchVault
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc DirectLaunchVaultBase
    function description() public view override returns (string memory) {
        string memory holdings = string.concat(
            "StreakVault of the ",
            PRODUCT_NAME,
            " round of launcher ",
            Strings.toHexString(launcher),
            ". It holds ",
            reservedTokens.toString(),
            " wei of reserved tokens (paid out so far: ",
            totalTokensPaid.toString(),
            ") and, in quote token ",
            Strings.toHexString(quoteToken),
            ", the prize (the part of the members' deposits that did not go to the pool) plus 80% of the trading tax as it arrives (received so far: ",
            quoteReceived().toString(),
            " wei; paid out: ",
            totalQuotePaid.toString(),
            " wei). "
        );
        return string.concat(
            holdings,
            "Members share both by the days each one checked in: a member with d of the ",
            totalCheckIns.toString(),
            " check-ins counted at launch can claim d/",
            totalCheckIns.toString(),
            " of the tokens once and d/",
            totalCheckIns.toString(),
            " of the quote received, again as more tax arrives. Members with no check-in receive nothing. The other 20% of the tax is burned. No fee, and no share for the creator, the sponsors or the attester ",
            Strings.toHexString(ICheckInLauncher(launcher).attester()),
            "; nobody can withdraw except a member through claim. Check-ins were signed by the attester (the app's server): they are attested, not proven."
        );
    }

    /// @inheritdoc DirectLaunchVaultBase
    function vaultUISchema() public pure override returns (VaultUISchema memory schema) {
        schema.vaultType = "StreakVault";
        schema.description = "Rewards of a check-in round: members share the reserved tokens, the prize from the "
            "deposits and 80% of the trading tax in proportion to the days each one checked in. Check-ins were "
            "signed by the round's attester. No fee; the creator, sponsors and attester receive nothing.";
        schema.methods = new VaultMethodSchema[](4);

        schema.methods[0].name = "claimable";
        schema.methods[0].description = "What a member can claim right now.";
        schema.methods[0].inputs = new FieldDescriptor[](1);
        schema.methods[0].inputs[0] = FieldDescriptor("member", "address", "A member of the round", 0);
        schema.methods[0].outputs = new FieldDescriptor[](2);
        schema.methods[0].outputs[0] = FieldDescriptor("tokenAmount", "uint256", "Claimable tokens", 18);
        schema.methods[0].outputs[1] = FieldDescriptor("quoteAmount", "uint256", "Claimable quote token", 18);

        schema.methods[1].name = "daysOf";
        schema.methods[1].description = "Days a member checked in. A member's share is this over totalCheckIns.";
        schema.methods[1].inputs = new FieldDescriptor[](1);
        schema.methods[1].inputs[0] = FieldDescriptor("member", "address", "A member of the round", 0);
        schema.methods[1].outputs = new FieldDescriptor[](1);
        schema.methods[1].outputs[0] = FieldDescriptor("days", "uint256", "Days checked in", 0);

        schema.methods[2].name = "quoteReceived";
        schema.methods[2].description = "Prize plus trading tax received by the vault so far.";
        schema.methods[2].outputs = new FieldDescriptor[](1);
        schema.methods[2].outputs[0] = FieldDescriptor("amount", "uint256", "Total quote token received", 18);

        schema.methods[3].name = "claim";
        schema.methods[3].description =
        "Claim the caller's share: tokens once, quote token again whenever more tax has arrived. No inputs.";
        schema.methods[3].isWriteMethod = true;
    }
}
