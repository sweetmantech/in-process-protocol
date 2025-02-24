// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

import {ERC20Z} from "../src/ERC20Z.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {DeployerBase} from "./DeployerBase.sol";

// Inherit from DeployerBase to get access to chain configuration
contract DeployScript is DeployerBase {
    function run() public {
        // Get protocol rewards from chain config
        IProtocolRewards protocolRewards = IProtocolRewards(PROTOCOL_REWARDS);
        
        // Get addresses from chain config
        address owner = getProxyAdmin();
        address zoraRecipient = getZoraRecipient();
        IWETH weth = IWETH(getWeth());
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(getNonFungiblePositionManager());

        vm.startBroadcast();

        // Deploy Royalties contract
        Royalties royalties = new Royalties();
        royalties.initialize(
            weth, 
            nonfungiblePositionManager, 
            payable(zoraRecipient),
            2500
        );

        // Deploy ERC20Z
        ERC20Z erc20z = new ERC20Z(royalties);

        // Deploy implementation first
        ZoraTimedSaleStrategyImpl impl = new ZoraTimedSaleStrategyImpl();

        // Then create a proxy pointing to the implementation
        bytes memory initData = abi.encodeWithSelector(
            ZoraTimedSaleStrategyImpl.initialize.selector,
            owner,
            zoraRecipient,
            address(erc20z),
            protocolRewards
        );

        // Deploy proxy with initialization data
        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Royalties deployed to:", address(royalties));
        console.log("ERC20Z deployed to:", address(erc20z));
        console.log("Sale Strategy Implementation deployed to:", address(impl));
    }
}
