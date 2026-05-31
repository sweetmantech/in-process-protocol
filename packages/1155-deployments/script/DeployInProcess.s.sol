// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreatorFixedPriceSaleStrategy} from "@zoralabs/zora-1155-contracts/src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ERC20Minter} from "@zoralabs/zora-1155-contracts/src/minters/erc20/ERC20Minter.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "@zoralabs/zora-1155-contracts/src/proxies/Zora1155Factory.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {ZoraDeployerBase} from "../src/ZoraDeployerBase.sol";
import {Deployment, ChainConfig} from "../src/DeploymentConfig.sol";

contract DeployInProcessMinimal is ZoraDeployerBase {
    // Reused from existing Zora mainnet deployments (no code changes needed)
    address constant REUSE_UPGRADE_GATE     = 0xbC50029836A59A4E5e1Bb8988272F46ebA0F9900;
    address constant REUSE_PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;

    function run() public returns (string memory) {
        ChainConfig memory chainConfig = getChainConfig();
        Deployment memory deployment = getDeployment();

        vm.startBroadcast();

        // 1. FixedPriceSaleStrategy — own deployment so only InProcess MintComment events are indexed
        ZoraCreatorFixedPriceSaleStrategy fixedPrice = new ZoraCreatorFixedPriceSaleStrategy();
        deployment.fixedPriceSaleStrategy = address(fixedPrice);
        console2.log("1. FixedPriceSaleStrategy:      ", address(fixedPrice));

        // 2. ERC20Minter — zero fee (rewardPct=0, ethReward=0)
        ERC20Minter erc20Minter = new ERC20Minter();
        erc20Minter.initialize(chainConfig.mintFeeRecipient, chainConfig.factoryOwner, 0, 0);
        deployment.erc20Minter = address(erc20Minter);
        console2.log("2. ERC20Minter:                 ", address(erc20Minter));

        // 3. ZoraCreator1155Impl — MINT_FEE=0 (modified fork)
        //    timedSaleStrategy=address(0) is allowed per constructor comment
        ZoraCreator1155Impl impl1155 = new ZoraCreator1155Impl(
            chainConfig.mintFeeRecipient,
            REUSE_UPGRADE_GATE,
            REUSE_PROTOCOL_REWARDS,
            address(0)
        );
        deployment.contract1155Impl = address(impl1155);
        deployment.contract1155ImplVersion = impl1155.contractVersion();
        console2.log("3. ZoraCreator1155Impl:         ", address(impl1155));

        // 4. ZoraCreator1155FactoryImpl
        //    merkleMinter=address(0), redeemMinterFactory=address(0) — not indexed, skipped
        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl(
            IZoraCreator1155(address(impl1155)),
            IMinter1155(address(0)),
            IMinter1155(address(fixedPrice)),
            IMinter1155(address(0))
        );
        deployment.factoryImpl = address(factoryImpl);
        console2.log("4. ZoraCreator1155FactoryImpl:  ", address(factoryImpl));

        // 5. Zora1155Factory proxy — InProcessCreatorFactory (SetupNewContract event source)
        bytes memory initData = abi.encodeWithSelector(
            ZoraCreator1155FactoryImpl.initialize.selector,
            chainConfig.factoryOwner
        );
        Zora1155Factory factoryProxy = new Zora1155Factory(address(factoryImpl), initData);
        deployment.factoryProxy = address(factoryProxy);
        console2.log("5. Zora1155Factory (proxy):     ", address(factoryProxy));

        vm.stopBroadcast();

        console2.log("\n--- Summary ---");
        console2.log("FIXED_PRICE_SALE_STRATEGY: ", deployment.fixedPriceSaleStrategy);
        console2.log("ERC20_MINTER:              ", deployment.erc20Minter);
        console2.log("CONTRACT_1155_IMPL:        ", deployment.contract1155Impl);
        console2.log("FACTORY_IMPL:              ", deployment.factoryImpl);
        console2.log("FACTORY_PROXY:             ", deployment.factoryProxy);

        return getDeploymentJSON(deployment);
    }
}
