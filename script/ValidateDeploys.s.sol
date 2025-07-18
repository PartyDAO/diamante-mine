/* solhint-disable gas-custom-errors */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1_2 } from "../src/DiamanteMineV1_2.sol";
import { DiamanteMineV1_2Dev } from "../src/DiamanteMineV1_2.dev.sol";
import { ByteHasher } from "../src/utils/ByteHasher.sol";
import { DeploymentConfig, StateType, Config, DevState, ProdState, StagingState } from "./config/DeploymentConfig.sol";

contract ValidateDeploysScript is Script {
    using ByteHasher for bytes;

    DiamanteMineV1_2 public prodImplementation = DiamanteMineV1_2(0x6180C3033Bf7A085AE5640E6480fb4D93eEBa5CC);
    DiamanteMineV1_2Dev public devImplementation = DiamanteMineV1_2Dev(0xba39c61a5B2d22B674c5E206f43BB949a5e31de0);

    // EIP-1967 storage slots
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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
            prodImplementation = new DiamanteMineV1_2(DeploymentConfig.PERMIT2);
            console.log("New DiamanteMineV1_2 implementation deployed to:", address(prodImplementation));
        }

        if (address(devImplementation) == address(0)) {
            devImplementation = new DiamanteMineV1_2Dev(DeploymentConfig.PERMIT2);
            console.log("New DiamanteMineV1_2Dev implementation deployed to:", address(devImplementation));
        }

        // 2. Upgrade each proxy to the appropriate implementation.
        uint256 upgradedCount = 0;
        uint256 manualUpgradeCount = 0;
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
                DiamanteMineV1_2 proxy = DiamanteMineV1_2(proxyAddress);
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
                DiamanteMineV1_2Dev proxy = DiamanteMineV1_2Dev(proxyAddress);
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
            address currentImplementation = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
            console.log("Current implementation:", currentImplementation);
            console.log("Target implementation: ", targetImplementation);

            // Check if the implementation is already the same
            if (currentImplementation == targetImplementation) {
                console.log("-> Proxy '%s' already uses the correct implementation. Skipping upgrade.", config.label);
                continue;
            }

            // Check if the caller has owner permissions
            if (!isCallerOwner(proxyAddress)) {
                console.log("! Warning: Caller is not the owner of proxy '%s'.", config.label);
                _logManualUpgradeInstructions(config.label, proxyAddress, targetImplementation, isProduction);
                manualUpgradeCount++;
                continue;
            }

            console.log("Upgrading proxy '%s'...", config.label);
            if (isProduction) {
                DiamanteMineV1_2(proxyAddress).upgradeToAndCall(targetImplementation, "");
            } else {
                DiamanteMineV1_2Dev(proxyAddress).upgradeToAndCall(targetImplementation, "");
            }

            upgradedCount++;
            console.log("Successfully upgraded proxy '%s'", config.label);
        }

        console.log("\nUpgrade process completed!");

        console.log("Total proxies:", configs.length);
        console.log("Successful upgrades:", upgradedCount);
        console.log("Skipped upgrades:", configs.length - upgradedCount - manualUpgradeCount);
        console.log("Manual upgrades needed:", manualUpgradeCount);

        vm.stopBroadcast();
    }

    function isCallerOwner(address proxyAddress) internal view returns (bool) {
        // Try to call owner() on the proxy - works for both production and dev versions
        try DiamanteMineV1_2(proxyAddress).owner() returns (address proxyOwner) {
            return proxyOwner == msg.sender;
        } catch {
            // Fallback to dev version if production version fails
            try DiamanteMineV1_2Dev(proxyAddress).owner() returns (address proxyOwner) {
                return proxyOwner == msg.sender;
            } catch {
                // If both fail, assume we don't have permission
                return false;
            }
        }
    }

    function _logManualUpgradeInstructions(
        string memory label,
        address proxyAddress,
        address targetImplementation,
        bool isProduction
    )
        internal
        view
    {
        console.log("\n=== MANUAL UPGRADE REQUIRED ===");
        console.log("Proxy '%s' requires manual upgrade by the owner.", label);
        console.log("Proxy address:           ", proxyAddress);
        console.log("Target implementation:   ", targetImplementation);

        // Get the proxy owner
        address proxyOwner;
        try DiamanteMineV1_2(proxyAddress).owner() returns (address owner) {
            proxyOwner = owner;
        } catch {
            try DiamanteMineV1_2Dev(proxyAddress).owner() returns (address owner) {
                proxyOwner = owner;
            } catch {
                proxyOwner = address(0);
            }
        }

        console.log("Proxy owner:             ", proxyOwner);
        console.log("Current caller:          ", msg.sender);

        console.log("\nTo upgrade manually, the owner should call:");
        if (isProduction) {
            console.log("DiamanteMineV1_2(proxyAddress).upgradeToAndCall(targetImplementation, \"\")");
        } else {
            console.log("DiamanteMineV1_2Dev(proxyAddress).upgradeToAndCall(targetImplementation, \"\")");
        }
        console.log("===============================\n");
    }

    function _validateDevState(DiamanteMineV1_2Dev proxy, string memory label) internal view {
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

    function _validateProdState(DiamanteMineV1_2 proxy, string memory label) internal view {
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

    function _validateStagingState(DiamanteMineV1_2Dev proxy, string memory label) internal view {
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
