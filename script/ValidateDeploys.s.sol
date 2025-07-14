/* solhint-disable gas-custom-errors */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";
import { DiamanteMineV1Dev } from "../src/DiamanteMineV1.dev.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ByteHasher } from "../src/utils/ByteHasher.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWorldID } from "../src/interfaces/IWorldID.sol";

enum StateType {
    Prod,
    Dev,
    Staging
}

struct Config {
    string label;
    address addr;
    string appId;
    string actionId;
    StateType stateType;
}

struct DevState {
    IERC20 diamante;
    IERC20 oro;
    IWorldID worldId;
    uint256 minAmountOro;
    uint256 maxAmountOro;
    uint256 minReward;
    uint256 extraRewardPerLevel;
    uint256 maxRewardLevel;
    uint256 referralBonusBps;
    uint256 miningInterval;
    string actionId;
}

struct ProdState {
    IERC20 diamante;
    IERC20 oro;
    IWorldID worldId;
    uint256 minAmountOro;
    uint256 maxAmountOro;
    uint256 minReward;
    uint256 extraRewardPerLevel;
    uint256 maxRewardLevel;
    uint256 referralBonusBps;
    uint256 miningInterval;
    string actionId;
}

struct StagingState {
    IERC20 diamante;
    IERC20 oro;
    IWorldID worldId;
    uint256 minAmountOro;
    uint256 maxAmountOro;
    uint256 minReward;
    uint256 extraRewardPerLevel;
    uint256 maxRewardLevel;
    uint256 referralBonusBps;
    uint256 miningInterval;
    string actionId;
}

contract ValidateDeploysScript is Script {
    using ByteHasher for bytes;

    // Production configuration
    ProdState public prodState = ProdState({
        diamante: IERC20(0x2ba918fec90Ca7AaC5753a2551593470815866e6),
        oro: IERC20(0xcd1E32B86953D79a6AC58e813D2EA7a1790cAb63),
        worldId: IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278),
        minAmountOro: 1 ether,
        maxAmountOro: 1 ether,
        minReward: 0.05 ether,
        extraRewardPerLevel: 0.08333 ether, // (0.8 - 0.05) / 9 = 0.08333...
        maxRewardLevel: 10,
        referralBonusBps: 10_000, // 100% bonus
        miningInterval: 24 hours,
        actionId: "mine"
    });

    // Development configuration for non-production environments
    DevState public devState = DevState({
        diamante: IERC20(0xFc46DC32F6Adb60d65012f7e943c3f29EB867796),
        oro: IERC20(0x27Ef8b2c8d843343243D7FF9445D6F7F283d911b),
        worldId: IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278),
        minAmountOro: 1 ether,
        maxAmountOro: 10 ether,
        minReward: 100 ether,
        extraRewardPerLevel: 50 ether,
        maxRewardLevel: 10,
        referralBonusBps: 500, // 5%
        miningInterval: 3 minutes,
        actionId: "mine"
    });

    // Staging configuration - combines dev token addresses with production reward parameters
    StagingState public stagingState = StagingState({
        diamante: IERC20(0xFc46DC32F6Adb60d65012f7e943c3f29EB867796),
        oro: IERC20(0x27Ef8b2c8d843343243D7FF9445D6F7F283d911b),
        worldId: IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278),
        minAmountOro: 1 ether,
        maxAmountOro: 10 ether,
        minReward: 100 ether,
        extraRewardPerLevel: 50 ether,
        maxRewardLevel: 10,
        referralBonusBps: 500, // 5%
        miningInterval: 3 minutes,
        actionId: "mine"
    });

    // Last Updated: 2025-07-14
    // From https://github.com/PartyDAO/partyworld/blob/staging/apps/diamante/src/config.ts#L25
    Config[] public configs = [
        Config({
            label: "production",
            addr: 0xb0036f162633b4eCFE11d5596368607C30a508aA,
            appId: "app_ab0484e59df747428e8207a21deeab98",
            actionId: "mine",
            stateType: StateType.Prod
        }),
        Config({
            label: "staging",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine",
            stateType: StateType.Staging
        }),
        Config({
            label: "preview",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine",
            stateType: StateType.Dev
        }),
        Config({
            label: "marcus",
            addr: 0xa09D833F625d6382FdA22A8282E58b076a49E589,
            appId: "app_44080323ee897f20dfbacdd30cedf2a8",
            actionId: "mine",
            stateType: StateType.Dev
        }),
        Config({
            label: "jeremy",
            addr: 0x2b6ceB2058FbCE142DCd2F0b5DD1B2d88436994D,
            appId: "app_af6f1a981af93b88be6e35c7d787964f",
            actionId: "mine",
            stateType: StateType.Dev
        }),
        Config({
            label: "steve",
            addr: 0x6a135F805203fA23dC301F474B9B9Dc8cBeb6b8c,
            appId: "app_2f15cba47775504177f6fa2729103ad6",
            actionId: "mine",
            stateType: StateType.Dev
        })
    ];

    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    DiamanteMineV1 public prodImplementation = DiamanteMineV1(0x0b2FE6e893c1344B9fB1B5E3ed6559E4D543e1cd);
    DiamanteMineV1Dev public devImplementation;

    function run() external {
        // Check if we have any proxies to upgrade
        if (configs.length == 0) {
            console.log("No proxy addresses configured. Please add proxy addresses to the configs array.");
            return;
        }

        vm.startBroadcast();

        // 1. Deploy the implementation contracts.
        if (address(prodImplementation) == address(0)) {
            prodImplementation = new DiamanteMineV1(PERMIT2);
            console.log("New DiamanteMineV1 implementation deployed to:", address(prodImplementation));
        }

        if (address(devImplementation) == address(0)) {
            devImplementation = new DiamanteMineV1Dev(PERMIT2);
            console.log("New DiamanteMineV1Dev implementation deployed to:", address(devImplementation));
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
                DiamanteMineV1 proxy = DiamanteMineV1(proxyAddress);
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
                DiamanteMineV1Dev proxy = DiamanteMineV1Dev(proxyAddress);
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
                DiamanteMineV1(proxyAddress).upgradeToAndCall(targetImplementation, "");
            } else {
                DiamanteMineV1Dev(proxyAddress).upgradeToAndCall(targetImplementation, "");
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

    function _validateDevState(DiamanteMineV1Dev proxy, string memory label) internal view {
        console.log("Validating dev configuration for '%s':", label);

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

    function _validateProdState(DiamanteMineV1 proxy, string memory label) internal view {
        console.log("Validating production configuration for '%s':", label);

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

    function _validateStagingState(DiamanteMineV1Dev proxy, string memory label) internal view {
        console.log("Validating staging configuration for '%s':", label);

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
