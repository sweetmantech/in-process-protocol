// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "@zoralabs/zora-1155-contracts/src/proxies/Zora1155Factory.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {DeploymentConfig, Deployment} from "../src/DeploymentConfig.sol";
import {ZoraDeployerBase} from "../src/ZoraDeployerBase.sol";

contract DeployFactoryProxy is ZoraDeployerBase {
    function run() public {
        // Get the deployment config to read existing contract addresses
        Deployment memory deployment = getDeployment();

        // Get the owner address from environment
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        vm.startBroadcast();

        // Deploy the factory proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            ZoraCreator1155FactoryImpl.initialize.selector,
            owner
        );
        Zora1155Factory factoryProxy = new Zora1155Factory(
            address(deployment.factoryImpl),
            initData
        );

        // Upgrade the proxy to point to the implementation
        ZoraCreator1155FactoryImpl(address(factoryProxy)).upgradeTo(address(deployment.factoryImpl));

        console2.log("Factory Proxy deployed at:", address(factoryProxy));
        console2.log("Factory Implementation deployed at:", address(deployment.factoryImpl));
        console2.log("Owner address:", owner);

        vm.stopBroadcast();

        // Update deployment struct with new factory proxy address
        deployment.factoryProxy = address(factoryProxy);

        // Use ZoraDeployerBase's getDeploymentJSON to update the addresses file
        getDeploymentJSON(deployment);
    }
} 