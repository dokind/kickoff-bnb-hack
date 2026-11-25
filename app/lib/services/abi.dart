/// Minimal ABI fragments: only the functions the app calls.
/// The full compiled ABIs are in ../contracts/abi/.
library;

import 'dart:convert';

import 'package:web3dart/web3dart.dart';

Map<String, dynamic> _fn(
  String name,
  List<String> inputs,
  List<String> outputs,
  String mutability,
) => {
  'type': 'function',
  'name': name,
  'stateMutability': mutability,
  'inputs': [
    for (var i = 0; i < inputs.length; i++) {'name': 'a$i', 'type': inputs[i]},
  ],
  'outputs': [
    for (var i = 0; i < outputs.length; i++)
      {'name': 'r$i', 'type': outputs[i]},
  ],
};

Map<String, dynamic> _view(
  String name,
  String output, [
  List<String>? inputs,
]) => _fn(name, inputs ?? const [], [output], 'view');

Map<String, dynamic> _tx(String name, [List<String>? inputs]) =>
    _fn(name, inputs ?? const [], const [], 'nonpayable');

ContractAbi _abi(String name, List<Map<String, dynamic>> items) =>
    ContractAbi.fromJson(jsonEncode(items), name);

/// Test USD quote token. `mint(address,uint256)` is open to anyone on testnet.
final erc20Abi = _abi('ERC20', [
  _view('balanceOf', 'uint256', ['address']),
  _view('allowance', 'uint256', ['address', 'address']),
  _tx('approve', ['address', 'uint256']),
  _tx('mint', ['address', 'uint256']),
]);

/// CheckInLauncher: one round (../contracts/abi/CheckInLauncher.json).
final checkInLauncherAbi = _abi('CheckInLauncher', [
  _view('deposit', 'uint256'),
  _view('liquidityBps', 'uint256'),
  _view('checkInGoal', 'uint256'),
  _view('deadline', 'uint256'),
  _view('isMember', 'bool', ['address']),
  _view('memberCount', 'uint256'),
  _view('daysOf', 'uint256', ['address']),
  _view('totalCheckIns', 'uint256'),
  _view('checkedInOn', 'bool', ['address', 'uint256']),
  _view('sponsoredBy', 'uint256', ['address']),
  _view('totalDeposits', 'uint256'),
  _view('totalSponsored', 'uint256'),
  _view('poolQuoteNow', 'uint256'),
  _view('prizeQuoteNow', 'uint256'),
  _view('refundable', 'uint256', ['address']),
  _view('launched', 'bool'),
  _view('token', 'address'),
  _view('vault', 'address'),
  _tx('join'),
  _tx('sponsor', ['uint256']),
  _tx('checkIn', ['uint256', 'bytes']),
  _tx('launch'),
  _tx('refund'),
]);

/// StreakVault: holds the prize, the reserved tokens and the trading tax
/// after launch (../contracts/abi/StreakVault.json).
final streakVaultAbi = _abi('StreakVault', [
  _fn('claimable', ['address'], ['uint256', 'uint256'], 'view'),
  _view('claimedTokens', 'uint256', ['address']),
  _view('claimedQuote', 'uint256', ['address']),
  _view('daysOf', 'uint256', ['address']),
  _view('totalCheckIns', 'uint256'),
  _tx('claim'),
]);

/// Flap Portal entry point
/// `newLauncher(address launcherFactory, bytes data) payable returns (address)`
/// must be sent with exactly `SALT_LOCK_FEE()` of tBNB.
final portalAbi = _abi('Portal', [
  _view('SALT_LOCK_FEE', 'uint256'),
  _fn('newLauncher', ['address', 'bytes'], ['address'], 'payable'),
]);

/// Not a real contract: only used to ABI-encode the `data` argument of
/// `newLauncher`, which is `abi.encode(RoundConfig)` with RoundConfig as one
/// tuple (see ../contracts/src/CheckInLauncherFactory.sol).
final roundConfigAbi = _abi('RoundConfig', [
  {
    'type': 'function',
    'name': 'config',
    'stateMutability': 'nonpayable',
    'outputs': <dynamic>[],
    'inputs': [
      {
        'name': 'c',
        'type': 'tuple',
        'components': [
          {'name': 'name', 'type': 'string'},
          {'name': 'symbol', 'type': 'string'},
          {'name': 'meta', 'type': 'string'},
          {'name': 'salt', 'type': 'bytes32'},
          {'name': 'deposit', 'type': 'uint256'},
          {'name': 'liquidityBps', 'type': 'uint256'},
          {'name': 'checkInGoal', 'type': 'uint256'},
          {'name': 'deadline', 'type': 'uint256'},
          {'name': 'attester', 'type': 'address'},
        ],
      },
    ],
  },
]);
