// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {IPortalTypes} from "src/flap/IPortal.sol";
import {Distribution, DistributionTarget} from "src/flap/Distribution.sol";
import {ILauncherFactory, LauncherRecord} from "src/flap/ILauncher.sol";
import {IDirectLaunchVaultFactory} from "src/flap/ILaunchVaultSpec.sol";
import {IStrategy} from "src/flap/IStrategy.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {CheckInLauncher, RoundConfig} from "src/CheckInLauncher.sol";
import {CheckInLauncherFactory} from "src/CheckInLauncherFactory.sol";
import {StreakVault} from "src/StreakVault.sol";
import {StreakVaultFactory} from "src/StreakVaultFactory.sol";

contract MockErc20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

interface ILaunching {
    function launching() external view returns (bool);
}

/// @dev Stands in for the Flap Portal in the unit tests. It follows the real launch closely enough for
///      our contracts to run their own code unchanged: it records Launchers, takes the salt lock, and on
///      a launch asks the vault factory for the vault, creates a token, pulls the pool's quote from the
///      Launcher and hands the reserved tokens to the vault through `initializeDistribution`. It can also
///      refuse a pool below a floor, like the real Portal. The real Portal is exercised in
///      `ShowupRound.fork.t.sol`.
///
///      The tests place this code at the Portal's real address (`vm.etch`), because the vault factory
///      and the vault only accept calls from that address. So: no constructor, no immutables.
contract MockPortal {
    uint256 public constant SALT_LOCK_FEE = 0.005 ether;
    address public constant POOL = address(0x9001);

    uint256 public launches;
    address public lastLaunchCaller;
    uint256 public lastPoolQuote;
    bool public launcherWasLaunching;
    /// @dev The liquidity floor. Zero means no floor.
    uint256 public floor;
    mapping(bytes32 salt => address) public saltLocker;
    mapping(address launcher => address) internal _factoryOf;
    mapping(address token => address) internal _vaultOf;
    mapping(address token => address) internal _vaultFactoryOf;

    error BelowFloor(uint256 poolQuote, uint256 floor);

    function setFloor(uint256 floor_) external {
        floor = floor_;
    }

    function lockSalt(bytes32 salt, uint8) external payable {
        require(msg.value == SALT_LOCK_FEE, "fee");
        saltLocker[salt] = msg.sender;
    }

    function newLauncher(address factory, bytes calldata data) external payable returns (address launcher) {
        launcher = ILauncherFactory(factory).newLauncher{value: msg.value}(msg.sender, data);
        _factoryOf[launcher] = factory;
    }

    function getLauncher(address launcher) external view returns (LauncherRecord memory) {
        return LauncherRecord({launcherFactory: _factoryOf[launcher]});
    }

    function launchTaxTokenV2(
        IPortalTypes.CreateTaxTokenParams calldata p,
        Distribution calldata d,
        IPortalTypes.CreatorBuyParams calldata
    ) external payable returns (address token, address pool) {
        require(saltLocker[p.salt] == msg.sender, "salt locked by another");
        if (p.poolQuote < floor) revert BelowFloor(p.poolQuote, floor);
        launches += 1;
        lastLaunchCaller = msg.sender;
        lastPoolQuote = p.poolQuote;
        launcherWasLaunching = ILaunching(msg.sender).launching();

        MockErc20 t = new MockErc20(p.name, p.symbol);
        t.mint(address(this), p.totalSupply);
        token = address(t);
        pool = POOL;

        address vault;
        for (uint256 i; i < p.feeConfigs.length; ++i) {
            if (p.feeConfigs[i].feeType != IPortalTypes.FeeSlotType.VAULT) continue;
            IPortalTypes.FeeConfigVault memory v = abi.decode(p.feeConfigs[i].configData, (IPortalTypes.FeeConfigVault));
            vault = IDirectLaunchVaultFactory(v.vaultFactory).newVault(token, msg.sender, 0, abi.encode(p, d));
            _vaultOf[token] = vault;
            _vaultFactoryOf[token] = v.vaultFactory;
        }

        IERC20(p.quoteToken).transferFrom(msg.sender, POOL, p.poolQuote);
        t.transfer(POOL, p.poolToken);
        if (d.target == DistributionTarget.VAULT) {
            t.approve(vault, d.amount);
            IStrategy(vault).initializeDistribution(token, d.amount, d.configData, p.salt);
        }
    }

    function getLaunchVault(address token) external view returns (address, address) {
        return (_vaultOf[token], _vaultFactoryOf[token]);
    }
}

/// @notice Shared setup for the unit tests: the two factories wired to a mock Portal that sits at the
///         Portal's real address, a mock quote token, one open round, and helpers to join, sponsor and
///         check in with an attester key the test holds. No RPC needed.
abstract contract RoundBase is Test {
    uint256 internal constant DEPOSIT = 1000 ether;
    uint256 internal constant LIQUIDITY_BPS = 3000;
    uint256 internal constant GOAL = 6;
    /// @dev 2026-11-26 01:00:00 UTC, one hour into UTC day 20783.
    uint256 internal constant START = 1795654800;

    uint256 internal constant ATTESTER_KEY = 0xA77E57E2;
    address internal attester;

    MockPortal internal portal;
    MockErc20 internal usd;
    CheckInLauncherFactory internal factory;
    StreakVaultFactory internal vaultFactory;
    CheckInLauncher internal launcher;

    address internal creator = address(0xC2EA702);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);
    address internal dave = address(0xDA7E);
    address internal sponsorWallet = address(0x5904502);
    address internal stranger = address(0x572A46E2);
    address internal guardian = address(0x6A2D);

    uint256 internal deadline;
    uint256 internal saltCounter;

    function setUp() public virtual {
        vm.chainId(97); // the vault factory and the vault resolve the Portal address per chain
        vm.warp(START);
        attester = vm.addr(ATTESTER_KEY);

        address hub = LaunchVaultAddresses.hub();
        vm.etch(hub, address(new MockPortal()).code);
        portal = MockPortal(hub);
        usd = new MockErc20("USD", "USD");

        // The two factories name each other, so the Launcher factory's address is predicted first.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        vaultFactory = new StreakVaultFactory(predicted);
        factory = new CheckInLauncherFactory(hub, guardian, address(vaultFactory), address(usd));
        assertEq(address(factory), predicted);

        deadline = START + 14 days;
        vm.deal(creator, 1 ether);
        launcher = _open(_config());
    }

    function _config() internal returns (RoundConfig memory c) {
        c.name = "Morning Movers";
        c.symbol = "MOVE";
        c.salt = bytes32(++saltCounter);
        c.deposit = DEPOSIT;
        c.liquidityBps = LIQUIDITY_BPS;
        c.checkInGoal = GOAL;
        c.deadline = deadline;
        c.attester = attester;
    }

    function _open(RoundConfig memory c) internal returns (CheckInLauncher) {
        vm.prank(creator);
        return CheckInLauncher(portal.newLauncher{value: 0.005 ether}(address(factory), abi.encode(c)));
    }

    function _today() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function _join(address member) internal {
        _join(launcher, member);
    }

    function _join(CheckInLauncher l, address member) internal {
        uint256 amount = l.deposit();
        usd.mint(member, amount);
        vm.startPrank(member);
        usd.approve(address(l), amount);
        l.join();
        vm.stopPrank();
    }

    function _sponsor(address who, uint256 amount) internal {
        _sponsor(launcher, who, amount);
    }

    function _sponsor(CheckInLauncher l, address who, uint256 amount) internal {
        usd.mint(who, amount);
        vm.startPrank(who);
        usd.approve(address(l), amount);
        l.sponsor(amount);
        vm.stopPrank();
    }

    /// @dev The digest built here independently of the contract, the way the verifier builds it:
    ///      personal_sign over keccak256(abi.encode(chainId, launcher, wallet, day)).
    function _digest(address l, address wallet, uint256 day) internal view returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(block.chainid, l, wallet, day));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
    }

    function _signWith(uint256 key, address l, address wallet, uint256 day) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(l, wallet, day));
        return abi.encodePacked(r, s, v);
    }

    function _sign(address wallet, uint256 day) internal view returns (bytes memory) {
        return _signWith(ATTESTER_KEY, address(launcher), wallet, day);
    }

    function _checkIn(address member, uint256 day) internal {
        _checkIn(launcher, member, day);
    }

    function _checkIn(CheckInLauncher l, address member, uint256 day) internal {
        bytes memory sig = _signWith(ATTESTER_KEY, address(l), member, day);
        vm.prank(member);
        l.checkIn(day, sig);
    }

    /// @dev Three members over two days, six check-ins: alice 3, bob 2, carol 1. Ends on the second day.
    function _fillTheBar() internal {
        _join(alice);
        _join(bob);
        _join(carol);
        uint256 d = _today();
        _checkIn(alice, d - 1);
        _checkIn(alice, d);
        _checkIn(bob, d);
        _checkIn(carol, d);
        vm.warp(block.timestamp + 1 days);
        _checkIn(alice, d + 1);
        _checkIn(bob, d + 1);
    }
}
