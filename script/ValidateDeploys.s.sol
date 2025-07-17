/* solhint-disable gas-custom-errors */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1_1 } from "../src/DiamanteMineV1_1.sol";
import { DiamanteMineV1_1Dev } from "../src/DiamanteMineV1_1.dev.sol";
import { ByteHasher } from "../src/utils/ByteHasher.sol";
import { DeploymentConfig, StateType, Config, DevState, ProdState, StagingState } from "./config/DeploymentConfig.sol";

contract ValidateDeploysScript is Script {
    using ByteHasher for bytes;

    DiamanteMineV1_1 public prodImplementation = DiamanteMineV1_1(0x0b2FE6e893c1344B9fB1B5E3ed6559E4D543e1cd);
    DiamanteMineV1_1Dev public devImplementation;

    function run() external {
        Config[] memory configs = DeploymentConfig.getConfigs();

        // Check if we have any proxies to upgrade
        if (configs.length == 0) {
            console.log("No proxy addresses configured. Please add proxy addresses to the configs array.");
            return;
        }

        vm.startBroadcast();

        // 1. Deploy the implementation contracts.
        if (address(prodImplementation) == address(0)) {
            prodImplementation = new DiamanteMineV1_1(DeploymentConfig.PERMIT2);
            console.log("New DiamanteMineV1_1 implementation deployed to:", address(prodImplementation));
        }

        if (address(devImplementation) == address(0)) {
            devImplementation = new DiamanteMineV1_1Dev(DeploymentConfig.PERMIT2);
            console.log("New DiamanteMineV1_1Dev implementation deployed to:", address(devImplementation));
        }

        // 2. Upgrade each proxy to the appropriate implementation.
        uint256 upgradedCount = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            Config memory config = configs[i];
            address proxyAddress = config.addr;
            console.log("Checking proxy '%s' at address:", config.label, proxyAddress);

            bool isProduction = config.stateType == StateType.Prod;
            address targetImplementation = isProduction ? address(prodImplementation) : address(devImplementation);

            // Check EXTERNAL_NULLIFIER
            uint256 expectedExternalNullifier =
                abi.encodePacked(abi.encodePacked(bytes(config.appId)).hashToField(), config.actionId).hashToField();

            if (isProduction) {
                DiamanteMineV1_1 proxy = DiamanteMineV1_1(proxyAddress);
                uint256 proxyExternalNullifier = proxy.EXTERNAL_NULLIFIER();

                if (proxyExternalNullifier != expectedExternalNullifier) {
                    console.log("! Incorrect EXTERNAL_NULLIFIER for proxy '%s'.", config.label);
                    console.log("  Expected:", expectedExternalNullifier);
                    console.log("  Actual:  ", proxyExternalNullifier);
                    revert("External nullifier mismatch");
                } else {
                    console.log(
                        "-> Proxy '%s' uses the correct EXTERNAL_NULLIFIER:", config.label, proxyExternalNullifier
                    );
                }

                // Validate production configuration
                _validateProdState(proxy, config.label);
            } else {
                DiamanteMineV1_1Dev proxy = DiamanteMineV1_1Dev(proxyAddress);
                uint256 proxyExternalNullifier = proxy.EXTERNAL_NULLIFIER();

                if (proxyExternalNullifier != expectedExternalNullifier) {
                    console.log("! Incorrect EXTERNAL_NULLIFIER for proxy '%s'.", config.label);
                    console.log("  Expected:", expectedExternalNullifier);
                    console.log("  Actual:  ", proxyExternalNullifier);
                    revert("External nullifier mismatch");
                } else {
                    console.log(
                        "-> Proxy '%s' uses the correct EXTERNAL_NULLIFIER:", config.label, proxyExternalNullifier
                    );
                }

                // Validate configuration based on state type
                if (config.stateType == StateType.Staging) {
                    _validateStagingState(proxy, config.label);
                } else {
                    _validateDevState(proxy, config.label);
                }
            }

            // Get the current implementation address by reading the EIP-1967 storage slot.
            bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
            address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, implementationSlot))));
            console.log("Current implementation:", currentImplementation);
            console.log("Target implementation: ", targetImplementation);

            // Check if the implementation is already the same
            if (currentImplementation == targetImplementation) {
                console.log("-> Proxy '%s' already uses the correct implementation. Skipping upgrade.", config.label);
                continue;
            }

            console.log("Upgrading proxy '%s'...", config.label);
            if (isProduction) {
                DiamanteMineV1_1(proxyAddress).upgradeToAndCall(targetImplementation, "");
            } else {
                DiamanteMineV1_1Dev(proxyAddress).upgradeToAndCall(targetImplementation, "");
            }

            upgradedCount++;
            console.log("Successfully upgraded proxy '%s'", config.label);
        }

        console.log("\nUpgrade process completed!");

        console.log("Total proxies:", configs.length);
        console.log("Successful upgrades:", upgradedCount);
        console.log("Skipped upgrades:", configs.length - upgradedCount);

        vm.stopBroadcast();
    }

    function _validateDevState(DiamanteMineV1_1Dev proxy, string memory label) internal view {
        console.log("Validating dev configuration for '%s':", label);

        DevState memory devState = DeploymentConfig.getDevState();

        // Check DIAMANTE token
        if (address(proxy.DIAMANTE()) != address(devState.diamante)) {
            console.log("! Incorrect DIAMANTE token for proxy '%s'.", label);
            console.log("  Expected:", address(devState.diamante));
            console.log("  Actual:  ", address(proxy.DIAMANTE()));
            revert("DIAMANTE token mismatch");
        }

        // Check ORO token
        if (address(proxy.ORO()) != address(devState.oro)) {
            console.log("! Incorrect ORO token for proxy '%s'.", label);
            console.log("  Expected:", address(devState.oro));
            console.log("  Actual:  ", address(proxy.ORO()));
            revert("ORO token mismatch");
        }

        console.log("-> Token addresses are correct for proxy '%s'", label);
    }

    function _validateProdState(DiamanteMineV1_1 proxy, string memory label) internal view {
        console.log("Validating production configuration for '%s':", label);

        ProdState memory prodState = DeploymentConfig.getProdState();

        // Skip validation if production config is not set (all zeros)
        if (address(prodState.diamante) == address(0)) {
            console.log("-> Production configuration not set, skipping validation for '%s'", label);
            return;
        }

        // Check DIAMANTE token
        if (address(proxy.DIAMANTE()) != address(prodState.diamante)) {
            console.log("! Incorrect DIAMANTE token for proxy '%s'.", label);
            console.log("  Expected:", address(prodState.diamante));
            console.log("  Actual:  ", address(proxy.DIAMANTE()));
            revert("DIAMANTE token mismatch");
        }

        // Check ORO token
        if (address(proxy.ORO()) != address(prodState.oro)) {
            console.log("! Incorrect ORO token for proxy '%s'.", label);
            console.log("  Expected:", address(prodState.oro));
            console.log("  Actual:  ", address(proxy.ORO()));
            revert("ORO token mismatch");
        }

        console.log("-> Token addresses are correct for proxy '%s'", label);
    }

    function _validateStagingState(DiamanteMineV1_1Dev proxy, string memory label) internal view {
        console.log("Validating staging configuration for '%s':", label);

        StagingState memory stagingState = DeploymentConfig.getStagingState();

        // Check DIAMANTE token
        if (address(proxy.DIAMANTE()) != address(stagingState.diamante)) {
            console.log("! Incorrect DIAMANTE token for proxy '%s'.", label);
            console.log("  Expected:", address(stagingState.diamante));
            console.log("  Actual:  ", address(proxy.DIAMANTE()));
            revert("DIAMANTE token mismatch");
        }

        // Check ORO token
        if (address(proxy.ORO()) != address(stagingState.oro)) {
            console.log("! Incorrect ORO token for proxy '%s'.", label);
            console.log("  Expected:", address(stagingState.oro));
            console.log("  Actual:  ", address(proxy.ORO()));
            revert("ORO token mismatch");
        }

        console.log("-> Token addresses are correct for proxy '%s'", label);
    }
}
