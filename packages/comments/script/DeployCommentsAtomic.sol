// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Comments} from "../src/proxy/Comments.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";

/// @notice Creates Comments proxy and initializes it in the same transaction
///         to prevent uninitialized-proxy frontrunning.
contract DeployCommentsAtomic {
    event Deployed(address indexed impl, address indexed proxy);

    address public immutable proxy;

    constructor(address impl, address defaultAdmin, address backfiller) {
        Comments commentsProxy = new Comments(impl);
        address[] memory delegateCommenters = new address[](0);
        CommentsImpl(payable(address(commentsProxy))).initialize(defaultAdmin, backfiller, delegateCommenters);
        proxy = address(commentsProxy);
        emit Deployed(impl, address(commentsProxy));
    }
}
