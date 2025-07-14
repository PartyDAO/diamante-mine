/* solhint-disable gas-custom-errors */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWorldID } from "../../src/interfaces/IWorldID.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

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

library DeploymentConfig {
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function getProdState() internal pure returns (ProdState memory) {
        return ProdState({
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
    }

    function getDevState() internal pure returns (DevState memory) {
        return DevState({
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
    }

    function getStagingState() internal pure returns (StagingState memory) {
        return StagingState({
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
    }

    function getConfigs() internal pure returns (Config[] memory) {
        // Last Updated: 2025-07-14
        // From https://github.com/PartyDAO/partyworld/blob/staging/apps/diamante/src/config.ts#L25
        Config[] memory configs = new Config[](6);

        configs[0] = Config({
            label: "production",
            addr: 0xb0036f162633b4eCFE11d5596368607C30a508aA,
            appId: "app_ab0484e59df747428e8207a21deeab98",
            actionId: "mine",
            stateType: StateType.Prod
        });

        configs[1] = Config({
            label: "staging",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine",
            stateType: StateType.Staging
        });

        configs[2] = Config({
            label: "preview",
            addr: 0x32b1747f4a94B376a63B21df7CaA29E82F411913,
            appId: "app_9a78cd265809afb0ce23e956b921428b",
            actionId: "mine",
            stateType: StateType.Dev
        });

        configs[3] = Config({
            label: "marcus",
            addr: 0xa09D833F625d6382FdA22A8282E58b076a49E589,
            appId: "app_44080323ee897f20dfbacdd30cedf2a8",
            actionId: "mine",
            stateType: StateType.Dev
        });

        configs[4] = Config({
            label: "jeremy",
            addr: 0x2b6ceB2058FbCE142DCd2F0b5DD1B2d88436994D,
            appId: "app_af6f1a981af93b88be6e35c7d787964f",
            actionId: "mine",
            stateType: StateType.Dev
        });

        configs[5] = Config({
            label: "steve",
            addr: 0x6a135F805203fA23dC301F474B9B9Dc8cBeb6b8c,
            appId: "app_2f15cba47775504177f6fa2729103ad6",
            actionId: "mine",
            stateType: StateType.Dev
        });

        return configs;
    }
}
