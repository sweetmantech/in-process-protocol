// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";

import {ERC20Z} from "../src/ERC20Z.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployScript is Script {
    // Base Sepolia addresses
    address constant PROTOCOL_REWARDS = 0x7777777722D078c97c6AD07d9f36801E653e356A;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant NFT_POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    address constant ZORA_RECIPIENT = 0x51027631B9DEF86e088C33368eC4E3A4BE0aD264;

    function run() public {
        vm.startBroadcast();

        // Deploy Royalties contract
        Royalties royalties = new Royalties();
        royalties.initialize(
            IWETH(WETH),
            INonfungiblePositionManager(NFT_POSITION_MANAGER),
            payable(ZORA_RECIPIENT),
            2500
        );

        // Deploy ERC20Z
        ERC20Z erc20z = new ERC20Z(royalties);

        // Deploy TimedSale implementation
        ZoraTimedSaleStrategyImpl impl = new ZoraTimedSaleStrategyImpl();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ZoraTimedSaleStrategyImpl.initialize.selector,
            msg.sender, // owner
            ZORA_RECIPIENT,
            address(erc20z),
            IProtocolRewards(PROTOCOL_REWARDS)
        );

        // Deploy proxy using TransparentUpgradeableProxy instead of ERC1967Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),    // implementation
            msg.sender,       // admin
            initData         // initialization call data
        );

        vm.stopBroadcast();

        console.log("Royalties deployed to:", address(royalties));
        console.log("ERC20Z deployed to:", address(erc20z));
        console.log("TimedSale Implementation deployed to:", address(impl));
        console.log("TimedSale Proxy deployed to:", address(proxy));
    }
}
