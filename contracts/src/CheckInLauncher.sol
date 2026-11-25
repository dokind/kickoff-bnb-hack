// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {IPortalTypes, IPortal} from "src/flap/IPortal.sol";
import {LauncherBase} from "src/flap/LauncherBase.sol";
import {Distribution, DistributionTarget} from "src/flap/Distribution.sol";
import {LaunchExtensionHelper} from "src/flap/LaunchExtensionHelper.sol";
import {LauncherDescription} from "src/flap/LauncherHelper.sol";
import {PRODUCT_NAME} from "./Product.sol";

// Display copy for `description()`. Chinese constants must be `unicode` literals. The Flap JSON helper
// does not escape these, so they must not contain a double quote or a backslash.
string constant ROUND_TITLE_SUFFIX_ZH = unicode"：打卡满格，代币才发射";
string constant ROUND_TITLE_SUFFIX_EN = ": check in to launch";
string constant ROUND_SUMMARY_ZH =
    unicode"带押金的自律打卡。每位成员一次性支付相同的押金，并在有运动的每一天打卡。每次打卡都需要证明方（应用的服务器）签名，签的是该钱包当天运动量达标：打卡是由证明方签署的，不是链上证明。所有成员的打卡共同填满一个进度条。进度条在截止时间前达到目标后，任何人都可以通过 Flap 发射代币：赞助资金加上押金中固定的一部分（见 liquidityBps）与一半供应进入资金池，LP 由 Flap 销毁。其余押金（奖金）、另一半供应和 80% 的交易税进入 StreakVault，由成员按各自的打卡天数比例分配；20% 的交易税被销毁。没有打卡的成员不参与分配。赞助人、创建者和证明方不获得任何分配。证明方不能发射代币，不能在进度条填满后阻止发射，也不能转移资金；它如果停止签名，进度条就填不满，所有人在截止时间后取回资金。若截止时间前没有发射，每位成员取回全部押金，每位赞助人取回其赞助金额。";
string constant ROUND_SUMMARY_EN =
    "A discipline round with a deposit on it. Each member pays the same deposit once and checks in on every day they move. Every check-in needs a signature from the attester (the app's server), which signs that the wallet moved enough that day: check-ins are attested, not proven. All check-ins fill one bar. Once the bar reaches its goal before the deadline, anyone can launch the token through Flap: sponsor money plus a fixed part of the deposits (see liquidityBps) seeds the pool with half the supply, and Flap burns the LP. The rest of the deposits (the prize), the other half of the supply and 80% of the trading tax go to a StreakVault, shared among members in proportion to the days each one checked in; 20% of the tax is burned. Members with no check-in receive nothing. Sponsors, the creator and the attester receive nothing. The attester cannot launch the token, cannot stop a launch once the bar is full and cannot move funds; if it stops signing, the bar never fills and everyone takes their money back after the deadline. If the token has not launched by the deadline, every member takes the full deposit back and every sponsor their contribution.";

/// @notice Payload for `Portal.newLauncher(factory, abi.encode(RoundConfig))`: ONE tuple
///         `(string,string,string,bytes32,uint256,uint256,uint256,uint256,address)` in this order.
/// @param name          Token name.
/// @param symbol        Token symbol.
/// @param meta          Metadata URI (may be empty).
/// @param salt          Launch salt, mined so the token address ends in `0x7777`.
/// @param deposit       Quote token every member pays once to join. Same for everyone.
/// @param liquidityBps  Part of the deposits that seeds the pool at launch, in basis points (3000 = 30%).
///                      The rest of the deposits is the prize.
/// @param checkInGoal   Check-ins, summed over all members, that fill the bar and open the launch.
/// @param deadline      Timestamp: the last moment to join, sponsor, check in and launch. After it, if the
///                      token has not launched, refunds open.
/// @param attester      The address whose signature every check-in must carry (the app's server key).
struct RoundConfig {
    string name;
    string symbol;
    string meta;
    bytes32 salt;
    uint256 deposit;
    uint256 liquidityBps;
    uint256 checkInGoal;
    uint256 deadline;
    address attester;
}

/// @title CheckInLauncher
/// @notice One round of a discipline app with money on it. One Launcher is one round.
///
///           join()      a wallet pays the fixed `deposit` once and becomes a member
///           sponsor()   optional: anyone adds quote that only ever goes to the launch pool
///           checkIn()   a member checks in for a UTC day; needs the attester's signature
///                       every check-in adds 1 to `daysOf[member]` and to `totalCheckIns` (the bar)
///           launch()    ANYONE, once `totalCheckIns >= checkInGoal`, no later than `deadline`:
///                         Portal.launchTaxTokenV2
///                           ├─ pool:  all sponsor money + `liquidityBps` of the deposits, half the supply
///                           ├─ StreakVault: the other half of the supply
///                           └─ tax:  80% to the StreakVault, 20% burned
///                         then the rest of the deposits (the prize) is sent to the StreakVault
///           refund()    after `deadline` with no launch: members take the full deposit back, sponsors
///                       their contribution
///
///         After the launch, members claim in the StreakVault in proportion to `daysOf`.
///
///         THE ATTESTER, PLAINLY. The attester is one address chosen when the round is created: the
///         app's server. It signs that a wallet moved enough on a given day, from phone health data, or
///         self-reported on the web. Check-ins are attested, not proven: this contract cannot see
///         anyone's activity and takes the signature as given, so the attester can sign for a member
///         who did not move, or refuse to sign for one who did.
///         What the attester can do: sign (or not sign) one check-in per member per UTC day, for the
///         current or the previous day only.
///         What it cannot do: launch early (the bar needs `checkInGoal` check-ins, each from a member
///         who paid a deposit), block or delay a launch once the bar is full (`launch()` is open to
///         anyone), choose who is paid in any way other than by signing daily check-ins, or move funds.
///         If it stops signing, the worst outcome is that the bar never fills and everyone is refunded.
///
///         Nobody can withdraw from this contract: not the attester, a sponsor, the creator or the
///         deployer. Quote leaves it only to the Flap pool and the StreakVault at launch, or back to
///         the wallet that paid it in a refund.
///
/// @dev Forked from Flap's `CrowdLauncher` example. Deployed by `CheckInLauncherFactory` as a beacon proxy.
contract CheckInLauncher is LauncherBase, Initializable {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;
    uint256 public constant POOL_TOKEN = TOTAL_SUPPLY / 2;
    uint256 public constant RESERVED_TOKEN = TOTAL_SUPPLY - POOL_TOKEN;
    /// @notice Share of the trading tax paid to the StreakVault. The rest is burned.
    uint16 public constant VAULT_TAX_BPS = 8000;
    uint256 public constant BPS = 10_000;

    address public hub;
    /// @notice The wallet that created the round. It has no rights here.
    address public creator;
    address public quoteToken;
    address public vaultFactory;
    /// @notice The address whose signature every check-in must carry. See the contract notice.
    address public attester;
    bytes32 public launchSalt;

    /// @notice Quote token every member pays once to join.
    uint256 public deposit;
    /// @notice Part of the deposits that seeds the pool at launch, in basis points.
    uint256 public liquidityBps;
    /// @notice Check-ins, summed over all members, that open the launch.
    uint256 public checkInGoal;
    /// @notice Joining, sponsoring, checking in and launching are possible up to and including this
    ///         timestamp. After it, refunds open if the token has not launched.
    uint256 public deadline;

    string public name;
    string public symbol;
    string public meta;

    uint256 public memberCount;
    mapping(address account => bool) public isMember;
    /// @notice Deposits held for members (`memberCount * deposit`). Frozen at launch.
    uint256 public totalDeposits;
    /// @notice Sponsor money held. Frozen at launch.
    uint256 public totalSponsored;
    mapping(address account => uint256 amount) public sponsoredBy;

    /// @notice Days each member checked in. Frozen at launch; the StreakVault pays by it.
    mapping(address member => uint256 count) public daysOf;
    /// @notice The bar: all check-ins of all members. Frozen at launch.
    uint256 public totalCheckIns;
    /// @notice Whether `member` checked in for UTC day `day` (`timestamp / 86400`).
    mapping(address member => mapping(uint256 day => bool)) public checkedInOn;

    bool public launched;
    /// @notice True only while the Portal launch call is running. The StreakVault factory reads it to
    ///         confirm the vault is being created by this very launch.
    bool public launching;

    address public token;
    address public pool;
    address public vault;
    /// @notice Quote sent to the StreakVault as the prize in the launch transaction. Zero before launch.
    uint256 public prizeQuote;

    event Joined(address indexed member, uint256 amount);
    event Sponsored(address indexed sponsor, uint256 amount);
    event CheckedIn(address indexed member, uint256 indexed day, uint256 daysOfMember, uint256 totalCheckIns);
    event Launched(
        address indexed token, address indexed pool, address indexed vault, uint256 poolQuote, uint256 prizeQuote
    );
    event Refunded(address indexed account, uint256 amount);

    error InvalidConfig();
    error LaunchInProgress();
    /// @notice Joining and sponsoring are over: the token launched or the deadline passed.
    error RoundClosed();
    error AlreadyMember();
    error ZeroAmount();
    error NotMember();
    /// @notice Check-ins are over: the token launched or the deadline passed.
    error CheckInsClosed();
    /// @notice `day` is neither the current UTC day nor the one before it.
    error InvalidDay(uint256 day, uint256 today);
    error AlreadyCheckedIn(uint256 day);
    /// @notice The signature is malformed or was not made by the attester for this wallet and day.
    error InvalidSignature();
    error AlreadyLaunched();
    error GoalNotReached(uint256 totalCheckIns, uint256 checkInGoal);
    /// @notice The deadline passed without a launch.
    error LaunchClosed();
    /// @notice Nothing would go to the pool: no sponsor money and no liquidity part of the deposits.
    error NoPoolQuote();
    error VaultMissing();
    /// @notice Refunds open strictly after the deadline, and only if the token never launched.
    error RefundUnavailable();
    error NothingToRefund();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Called once by the factory, which has already validated `c`.
    function initialize(
        address hub_,
        address creator_,
        address quoteToken_,
        address vaultFactory_,
        RoundConfig calldata c
    ) external payable initializer {
        if (hub_ == address(0) || creator_ == address(0) || quoteToken_ == address(0) || vaultFactory_ == address(0)) {
            revert InvalidConfig();
        }

        hub = hub_;
        creator = creator_;
        quoteToken = quoteToken_;
        vaultFactory = vaultFactory_;
        attester = c.attester;
        launchSalt = c.salt;
        deposit = c.deposit;
        liquidityBps = c.liquidityBps;
        checkInGoal = c.checkInGoal;
        deadline = c.deadline;
        name = c.name;
        symbol = c.symbol;
        meta = c.meta;

        // The Launcher locks the salt itself, so the Portal records it as the locker.
        uint256 fee = IPortal(hub_).SALT_LOCK_FEE();
        // Exactly the fee: anything extra would be stuck here.
        if (msg.value != fee) revert InvalidConfig();
        IPortal(hub_).lockSalt{value: fee}(c.salt, uint8(IPortalTypes.LaunchKind.DIRECT_V2_POOL_TAX));
    }

    function _getHub() internal view override returns (address) {
        return hub;
    }

    /// @inheritdoc LauncherBase
    /// @dev `targetRaise` is 0 on purpose: this round has no raise target. The launch opens on check-ins,
    ///      not on money in. What would seed the pool right now is `poolQuoteNow()`.
    function _description() internal view override returns (LauncherDescription memory d) {
        d.name = name;
        d.symbol = symbol;
        d.quoteToken = quoteToken;
        d.targetRaise = 0;
        d.poolTokenRatio = (POOL_TOKEN * 1e18) / TOTAL_SUPPLY;
        d.titleZh = string.concat(PRODUCT_NAME, ROUND_TITLE_SUFFIX_ZH);
        d.titleEn = string.concat(PRODUCT_NAME, ROUND_TITLE_SUFFIX_EN);
        d.summaryZh = ROUND_SUMMARY_ZH;
        d.summaryEn = ROUND_SUMMARY_EN;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The current UTC day number, `block.timestamp / 86400`. `checkIn` accepts this day and the
    ///         one before it.
    function currentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice What `launch()` would seed the pool with right now: all sponsor money plus `liquidityBps`
    ///         of the deposits. Flap's Portal enforces a liquidity floor at launch and reverts below it,
    ///         so show this next to the floor. Unchanged after the launch (the totals are frozen).
    function poolQuoteNow() public view returns (uint256) {
        return totalSponsored + (totalDeposits * liquidityBps) / BPS;
    }

    /// @notice The prize: what `launch()` would send to the StreakVault right now, which is everything
    ///         this contract holds that does not go to the pool. After the launch, what was sent.
    function prizeQuoteNow() public view returns (uint256) {
        if (launched) return prizeQuote;
        return IERC20(quoteToken).balanceOf(address(this)) - poolQuoteNow();
    }

    /// @notice True when `launch()` would pass this contract's own checks right now. The Portal can still
    ///         revert the launch if `poolQuoteNow()` is below its liquidity floor.
    function canLaunch() external view returns (bool) {
        return !launched && totalCheckIns >= checkInGoal && block.timestamp <= deadline && poolQuoteNow() != 0;
    }

    /// @notice What `account` would receive from `refund()` right now: zero while refunds are closed.
    function refundable(address account) public view returns (uint256 amount) {
        if (launched || block.timestamp <= deadline) return 0;
        amount = sponsoredBy[account];
        if (isMember[account]) amount += deposit;
    }

    /// @notice The hash the attester signs for `wallet` checking in on `day`:
    ///
    ///           inner  = keccak256(abi.encode(uint256 block.chainid, address this, address wallet, uint256 day))
    ///           digest = keccak256("\x19Ethereum Signed Message:\n32" ++ inner)
    ///
    ///         That is `personal_sign` (EIP-191) of the 32 raw bytes of `inner`. The chain id and this
    ///         contract's address are part of it, so a signature works for one round on one chain only.
    function checkInDigest(address wallet, uint256 day) public view returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(keccak256(abi.encode(block.chainid, address(this), wallet, day)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Joining and sponsoring
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Join the round: pulls `deposit` of the quote token from the caller (approve first). Once
    ///         per address, until the launch or the deadline.
    function join() external {
        if (launching) revert LaunchInProgress();
        if (launched || block.timestamp > deadline) revert RoundClosed();
        if (isMember[msg.sender]) revert AlreadyMember();

        isMember[msg.sender] = true;
        memberCount += 1;
        totalDeposits += deposit;
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), deposit);
        emit Joined(msg.sender, deposit);
    }

    /// @notice Add `amount` of the quote token to the launch pool (approve first). Optional and open to
    ///         anyone, any number of times, until the launch or the deadline. Sponsor money only ever
    ///         goes to the pool: it earns no share of the tokens, the prize or the tax. If the round
    ///         does not launch, the sponsor takes it back with `refund()`.
    function sponsor(uint256 amount) external {
        if (launching) revert LaunchInProgress();
        if (launched || block.timestamp > deadline) revert RoundClosed();
        if (amount == 0) revert ZeroAmount();

        sponsoredBy[msg.sender] += amount;
        totalSponsored += amount;
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Sponsored(msg.sender, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Checking in
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Check in for a UTC day. Members only, once per wallet per day, for the current day or the
    ///         one before it, until the launch or the deadline.
    /// @param day        UTC day number, `timestamp / 86400`.
    /// @param signature  The attester's 65-byte signature (`r ++ s ++ v`, v = 27 or 28) over
    ///                   `checkInDigest(msg.sender, day)`.
    function checkIn(uint256 day, bytes calldata signature) external {
        if (launching) revert LaunchInProgress();
        if (launched || block.timestamp > deadline) revert CheckInsClosed();
        if (!isMember[msg.sender]) revert NotMember();
        uint256 today = currentDay();
        if (day > today || day + 1 < today) revert InvalidDay(day, today);
        if (checkedInOn[msg.sender][day]) revert AlreadyCheckedIn(day);

        (address signer, ECDSA.RecoverError err) = ECDSA.tryRecover(checkInDigest(msg.sender, day), signature);
        if (err != ECDSA.RecoverError.NoError || signer != attester) revert InvalidSignature();

        checkedInOn[msg.sender][day] = true;
        uint256 memberDays = daysOf[msg.sender] + 1;
        daysOf[msg.sender] = memberDays;
        uint256 total = totalCheckIns + 1;
        totalCheckIns = total;
        emit CheckedIn(msg.sender, day, memberDays, total);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Launch
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Launch the token through Flap. Open to ANYONE, once, when the bar is full
    ///         (`totalCheckIns >= checkInGoal`) and the deadline has not passed. No address has a say
    ///         in it beyond that: not the attester, not the creator.
    /// @dev The pool gets `poolQuoteNow()`; everything else this contract holds is the prize and goes to
    ///      the StreakVault in the same transaction. If the pool money is below Flap's floor the Portal
    ///      reverts the whole call and nothing changes; a sponsor can then top the pool up.
    function launch() external {
        if (launching) revert LaunchInProgress();
        if (launched) revert AlreadyLaunched();
        if (totalCheckIns < checkInGoal) revert GoalNotReached(totalCheckIns, checkInGoal);
        if (block.timestamp > deadline) revert LaunchClosed();
        uint256 poolQuote = poolQuoteNow();
        if (poolQuote == 0) revert NoPoolQuote();

        IPortalTypes.CreateTaxTokenParams memory p = _buildParams(poolQuote);
        // The reserved half goes straight to this launch's StreakVault.
        Distribution memory dist = Distribution({
            target: DistributionTarget.VAULT, strategy: address(0), amount: uint128(RESERVED_TOKEN), configData: ""
        });
        IPortalTypes.CreatorBuyParams memory noCreatorBuy;

        // ERC-20 quote: the Portal pulls the pool's quote from this contract, so no native value is sent.
        IERC20 quote = IERC20(quoteToken);
        quote.forceApprove(hub, poolQuote);
        launching = true;
        (address token_, address pool_) = IPortal(hub).launchTaxTokenV2(p, dist, noCreatorBuy);
        launching = false;
        launched = true;
        quote.forceApprove(hub, 0);

        (address vault_,) = IPortal(hub).getLaunchVault(token_);
        if (vault_ == address(0)) revert VaultMissing();

        // Whatever is left here is the prize: the deposits minus their liquidity part.
        uint256 prize = quote.balanceOf(address(this));
        token = token_;
        pool = pool_;
        vault = vault_;
        prizeQuote = prize;
        if (prize != 0) quote.safeTransfer(vault_, prize);
        emit Launched(token_, pool_, vault_, poolQuote, prize);
    }

    function _buildParams(uint256 poolQuote) private view returns (IPortalTypes.CreateTaxTokenParams memory p) {
        p.name = name;
        p.symbol = symbol;
        p.meta = meta;
        p.totalSupply = TOTAL_SUPPLY;
        p.salt = launchSalt;
        p.quoteToken = quoteToken;
        p.dexId = 0;
        p.poolQuote = poolQuote;
        p.poolToken = POOL_TOKEN;
        p.buyTaxRate = 300;
        p.sellTaxRate = 500;
        p.taxDuration = 30 days;
        p.antiFarmerDuration = 1 days;
        p.feeConfigs = _feeConfigs();
        p.exemptAddrs = new address[](0);
        (p.extensionID, p.extensionData) = LaunchExtensionHelper.encodeCreator(creator);
    }

    /// @dev Tax split: 80% to the StreakVault, 20% burned. No marketing wallet, no creator share.
    function _feeConfigs() private view returns (IPortalTypes.FeeConfig[] memory fees) {
        fees = new IPortalTypes.FeeConfig[](2);
        fees[0] = IPortalTypes.FeeConfig({
            feeType: IPortalTypes.FeeSlotType.VAULT,
            bps: VAULT_TAX_BPS,
            configData: abi.encode(
                IPortalTypes.FeeConfigVault({vaultFactory: vaultFactory, vaultData: abi.encode(address(this))})
            )
        });
        fees[1] = IPortalTypes.FeeConfig({
            feeType: IPortalTypes.FeeSlotType.DEFLATION, bps: uint16(BPS) - VAULT_TAX_BPS, configData: ""
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Refund
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Take your money back from a round that did not launch: the full deposit if the caller is a
    ///         member, plus everything the caller sponsored. Only strictly after the deadline, and only
    ///         if the token never launched. Each wallet is paid what it paid in, nothing else.
    function refund() external {
        // Strictly after the deadline: `launch()` is still allowed at `deadline` itself.
        if (launched || block.timestamp <= deadline) revert RefundUnavailable();

        uint256 amount = sponsoredBy[msg.sender];
        if (amount != 0) {
            sponsoredBy[msg.sender] = 0;
            totalSponsored -= amount;
        }
        if (isMember[msg.sender]) {
            isMember[msg.sender] = false;
            memberCount -= 1;
            totalDeposits -= deposit;
            amount += deposit;
        }
        if (amount == 0) revert NothingToRefund();

        IERC20(quoteToken).safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, amount);
    }
}
