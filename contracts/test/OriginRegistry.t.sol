// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {OriginRegistry} from "../src/OriginRegistry.sol";

contract OriginRegistryTest is Test {
    address internal announcer = makeAddr("announcer");
    OriginRegistry internal registry;

    event OriginChanged(string origin);

    function setUp() public {
        registry = new OriginRegistry(announcer);
    }

    function test_StartsEmpty() public view {
        assertEq(registry.origin(), "");
        assertEq(registry.updatedAt(), 0);
        assertEq(registry.announcer(), announcer);
    }

    function test_AnnouncerSetsOrigin() public {
        vm.warp(1_795_000_000);
        vm.expectEmit();
        emit OriginChanged("one.trycloudflare.com");
        vm.prank(announcer);
        registry.setOrigin("one.trycloudflare.com");
        assertEq(registry.origin(), "one.trycloudflare.com");
        assertEq(registry.updatedAt(), 1_795_000_000);
    }

    function test_AnnouncerCanMoveTheOrigin() public {
        vm.startPrank(announcer);
        registry.setOrigin("one.trycloudflare.com");
        registry.setOrigin("two.trycloudflare.com");
        vm.stopPrank();
        assertEq(registry.origin(), "two.trycloudflare.com");
    }

    function test_OthersCannotSetOrigin() public {
        vm.expectRevert(OriginRegistry.NotAnnouncer.selector);
        registry.setOrigin("evil.example");
    }

    function test_EmptyOriginIsRefused() public {
        vm.prank(announcer);
        vm.expectRevert(OriginRegistry.EmptyOrigin.selector);
        registry.setOrigin("");
    }

    function test_ZeroAnnouncerIsRefused() public {
        vm.expectRevert(OriginRegistry.ZeroAnnouncer.selector);
        new OriginRegistry(address(0));
    }
}
