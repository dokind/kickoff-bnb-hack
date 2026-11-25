// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ClonesUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";

/// @notice Pins the salt rule documented in the README, so the app or the verifier can mine a salt
///         off-chain with one keccak per attempt: the club token is an EIP-1167 clone the Portal deploys
///         with CREATE2, and the Portal requires its address to end in 0x7777.
contract SaltTest is Test {
    address internal constant PORTAL = 0x000042108465206185A077Edc3F3fd2b49060000;
    address internal constant TOKEN_IMPL = 0x7777c57ff7dc441c1715b2e36fa581c48B782222;
    /// @dev keccak256 of the clone's creation code for TOKEN_IMPL. Quoted in the README.
    bytes32 internal constant TOKEN_INIT_CODE_HASH = keccak256(
        abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73", TOKEN_IMPL, hex"5af43d82803e903d91602b57fd5bf3")
    );

    function test_documentedFormulaMatchesTheClonePrediction(bytes32 salt) public pure {
        address documented =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), PORTAL, salt, TOKEN_INIT_CODE_HASH)))));
        assertEq(documented, ClonesUpgradeable.predictDeterministicAddress(TOKEN_IMPL, salt, PORTAL));
    }

    function test_logInitCodeHash() public {
        emit log_named_bytes32("TOKEN_INIT_CODE_HASH", TOKEN_INIT_CODE_HASH);
    }
}
