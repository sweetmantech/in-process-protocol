// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ScriptBase.sol";
import {stdJson} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolRewards} from "../src/ProtocolRewards.sol";

contract DeployScript is ScriptBase {
    using stdJson for string;

    function run() public {
        vm.startBroadcast();

        ProtocolRewards protocolRewards = new ProtocolRewards();
        console2.log("PROTOCOL REWARDS DEPLOYED:");
        console2.logAddress(address(protocolRewards));

        vm.stopBroadcast();
    }
}
