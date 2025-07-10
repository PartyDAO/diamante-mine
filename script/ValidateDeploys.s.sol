// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ByteHasher } from "../src/utils/ByteHasher.sol";

struct Config {
    string label;
    address addr;
    string appId;
    string actionId;
}

contract ValidateDeploysScript is Script {
    using ByteHasher for bytes;

    Config[] public configs = [
        Config({
            label: "production",
            addr: 0x707670dBD7bD05b744D428A663BE634bC5E7Da96,
            appId: "app_ab0484e59df747428e8207a21deeab98",
            actionId: "mine"
        }),
        Config({
            label: "staging",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine"
        }),
        Config({
            label: "preview",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine"
        }),
        Config({
            label: "marcus",
            addr: 0xa09D833F625d6382FdA22A8282E58b076a49E589,
            appId: "app_44080323ee897f20dfbacdd30cedf2a8",
            actionId: "mine"
        }),
        Config({
            label: "jeremy",
            addr: 0x2b6ceB2058FbCE142DCd2F0b5DD1B2d88436994D,
            appId: "app_af6f1a981af93b88be6e35c7d787964f",
            actionId: "mine"
        }),
        Config({
            label: "steve",
            addr: 0x6a135F805203fA23dC301F474B9B9Dc8cBeb6b8c,
            appId: "app_2f15cba47775504177f6fa2729103ad6",
            actionId: "mine"
        })
    ];

    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    DiamanteMineV1 public implementation = DiamanteMineV1(0x0b2FE6e893c1344B9fB1B5E3ed6559E4D543e1cd);

    function run() external {
        // Check if we have any proxies to upgrade
        if (configs.length == 0) {
            console.log("No proxy addresses configured. Please add proxy addresses to the configs array.");
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
        for (uint256 i = 0; i < configs.length; i++) {
            Config memory config = configs[i];
            address proxyAddress = config.addr;
            console.log("Checking proxy '%s' at address:", config.label, proxyAddress);

            DiamanteMineV1 proxy = DiamanteMineV1(proxyAddress);

            // Check EXTERNAL_NULLIFIER
            uint256 expectedExternalNullifier =
                abi.encodePacked(abi.encodePacked(bytes(config.appId)).hashToField(), config.actionId).hashToField();
            uint256 proxyExternalNullifier = proxy.EXTERNAL_NULLIFIER();

            if (proxyExternalNullifier != expectedExternalNullifier) {
                console.log("! Incorrect EXTERNAL_NULLIFIER for proxy '%s'.", config.label);
                console.log("  Expected:", expectedExternalNullifier);
                console.log("  Actual:  ", proxyExternalNullifier);
                // solhint-disable-next-line gas-custom-errors
                revert("External nullifier mismatch");
            } else {
                console.log("-> Proxy '%s' uses the correct EXTERNAL_NULLIFIER:", config.label, proxyExternalNullifier);
            }

            // Get the current implementation address by reading the EIP-1967 storage slot.
            bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
            address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
            console.log("Current implementation:", currentImplementation);
            console.log("New implementation:    ", address(implementation));

            // Check if the implementation is already the same
            if (currentImplementation == address(implementation)) {
                console.log("-> Proxy '%s' already uses the latest implementation. Skipping upgrade.", config.label);
                continue;
            }

            console.log("Upgrading proxy '%s'...", config.label);
            proxy.upgradeToAndCall(address(implementation), "");

            upgradedCount++;
            console.log("Successfully upgraded proxy '%s'", config.label);
        }

        console.log("\nUpgrade process completed!");

        console.log("Total proxies:", configs.length);
        console.log("Successful upgrades:", upgradedCount);
        console.log("Skipped upgrades:", configs.length - upgradedCount);

        vm.stopBroadcast();
    }
}
