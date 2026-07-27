// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";

/// @notice Non-deterministic deploy of In Process Comments (proxy + impl only).
contract DeployInProcessComments is Script {
    using stdJson for string;

    uint256 internal constant SPARK_VALUE = 0.000001 ether;
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant BACKFILLER = 0x77baCD258d2E6A5187B7344419A5e2842A49A059;

    function run() public {
        string memory chainConfigPath = string.concat("../shared-contracts/chainConfigs/", vm.toString(block.chainid), ".json");
        string memory chainConfig = vm.readFile(chainConfigPath);

        address defaultAdmin = chainConfig.readAddress(".PROXY_ADMIN");
        address zoraRecipient = chainConfig.readAddress(".ZORA_RECIPIENT");

        vm.startBroadcast();

        CommentsImpl impl = new CommentsImpl(SPARK_VALUE, PROTOCOL_REWARDS, zoraRecipient);
        Comments proxy = new Comments(address(impl));

        address[] memory delegateCommenters = new address[](0);
        CommentsImpl(payable(address(proxy))).initialize(defaultAdmin, BACKFILLER, delegateCommenters);

        vm.stopBroadcast();

        console2.log("In Process Comments Impl:", address(impl));
        console2.log("In Process Comments Proxy:", address(proxy));
        console2.log("defaultAdmin:", defaultAdmin);

        _saveAddresses(address(impl), address(proxy));
    }

    function _saveAddresses(address impl, address proxy) internal {
        string memory objectKey = "config";
        vm.serializeAddress(objectKey, "COMMENTS", proxy);
        vm.serializeAddress(objectKey, "COMMENTS_IMPL", impl);
        vm.serializeUint(objectKey, "COMMENTS_BLOCK_NUMBER", block.number);
        string memory result = vm.serializeUint(objectKey, "COMMENTS_IMPL_BLOCK_NUMBER", block.number);
        string memory path = string.concat("./addresses/inprocess-", vm.toString(block.chainid), ".json");
        vm.writeJson(result, path);
    }
}
