// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title OriginRegistry
/// @notice Where the product's server can be reached right now. The server's own key (the same key
///         that attests check-ins) writes its current host here whenever it changes, and the apps
///         read it before their first call. No address is baked into a build, so the server can
///         move without anyone reinstalling anything.
/// @dev    Holds no funds and gates nothing on chain. A wrong value can only make the apps call a
///         server that cannot sign check-ins, because check-ins are verified against the
///         attester's signature by each round's launcher.
contract OriginRegistry {
    /// @notice The only address that may set the origin: the server's key.
    address public immutable announcer;

    /// @notice The server's host, without scheme or path (for example "name.trycloudflare.com").
    string public origin;

    /// @notice Block time of the last change.
    uint256 public updatedAt;

    event OriginChanged(string origin);

    error NotAnnouncer();
    error EmptyOrigin();
    error ZeroAnnouncer();

    constructor(address announcer_) {
        if (announcer_ == address(0)) revert ZeroAnnouncer();
        announcer = announcer_;
    }

    /// @notice Record the server's current host.
    function setOrigin(string calldata origin_) external {
        if (msg.sender != announcer) revert NotAnnouncer();
        if (bytes(origin_).length == 0) revert EmptyOrigin();
        origin = origin_;
        updatedAt = block.timestamp;
        emit OriginChanged(origin_);
    }
}
