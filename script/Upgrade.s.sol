// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeScript is Script {
    address[] public proxies = [
        0xb0036f162633b4eCFE11d5596368607C30a508aA, // Production
        0x707670dBD7bD05b744D428A663BE634bC5E7Da96, // Staging
        0x2b6ceB2058FbCE142DCd2F0b5DD1B2d88436994D, // Jeremy
        0x6a135F805203fA23dC301F474B9B9Dc8cBeb6b8c, // Steve
        0xa09D833F625d6382FdA22A8282E58b076a49E589 // Marcus
    ];

    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    DiamanteMineV1 public implementation = DiamanteMineV1(0x0b2FE6e893c1344B9fB1B5E3ed6559E4D543e1cd);

    function run() external {
        // Check if we have any proxies to upgrade
        if (proxies.length == 0) {
            console.log("No proxy addresses configured. Please add proxy addresses to the proxies array.");
            return;
        }

        vm.startBroadcast();

        // 1. Deploy the new implementation contract.
        if (address(implementation) == address(0)) {
            implementation = new DiamanteMineV1(PERMIT2);
            console.log("New DiamanteMineV1 implementation deployed to:", address(implementation));
        }

        // 2. Upgrade each proxy to the new implementation.
        uint256 upgradedCount = 0;
        for (uint256 i = 0; i < proxies.length; i++) {
            address proxyAddress = proxies[i];
            console.log("Checking proxy at address:", proxyAddress);

            // Get the current implementation address by reading the EIP-1967 storage slot.
            bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
            address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
            console.log("Current implementation:", currentImplementation);
            console.log("New implementation:", address(implementation));

            // Check if the implementation is already the same
            if (currentImplementation == address(implementation)) {
                console.log("Proxy", i + 1, "already uses the same implementation. Skipping upgrade.");
                continue;
            }

            console.log("Upgrading proxy", i + 1, "of", proxies.length);
            DiamanteMineV1 proxy = DiamanteMineV1(proxyAddress);
            proxy.upgradeToAndCall(address(implementation), "");

            upgradedCount++;
            console.log("Successfully upgraded proxy", i + 1);
        }

        console.log("Upgrade process completed!");

        console.log("Total proxies:", proxies.length);
        console.log("Successful upgrades:", upgradedCount);
        console.log("Skipped upgrades:", proxies.length - upgradedCount);

        vm.stopBroadcast();
    }
}
