// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { DiamanteMineV1_2 } from "../src/DiamanteMineV1_2.sol";
import { IWorldID } from "../src/interfaces/IWorldID.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployUpgradeableProd is Script {
    ISignatureTransfer public PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    IERC20 public constant DIAMANTE = IERC20(0x2ba918fec90Ca7AaC5753a2551593470815866e6);
    IERC20 public constant ORO = IERC20(0xcd1E32B86953D79a6AC58e813D2EA7a1790cAb63);

    string public constant APP_ID = "app_ab0484e59df747428e8207a21deeab98";

    function run() external returns (address proxyAddress) {
        vm.startBroadcast();

        // Deploy implementation
        DiamanteMineV1_2 implementation = new DiamanteMineV1_2(PERMIT2);
        console.log("DiamanteMineV1_2 implementation deployed to:", address(implementation));

        // Set deployment parameters
        IWorldID worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
        uint256 minAmountOro = 1 ether;
        uint256 maxAmountOro = 1 ether;
        uint256 minReward = 0.05 ether;
        uint256 extraRewardPerLevel = 0.08333 ether; // (0.8 - 0.05) / 9 = 0.08333...
        uint256 maxRewardLevel = 10;
        uint256 referralBonusBps = 10_000; // 100% bonus
        uint256 miningInterval = 24 hours;
        // TODO: Set variables
        uint40 streakWindow;
        uint256 streakBonusBps;
        string memory actionId = "mine";

        // Prepare initialization data
        bytes memory data = abi.encodeWithSelector(
            DiamanteMineV1_2.initialize.selector,
            msg.sender,
            DIAMANTE,
            ORO,
            minAmountOro,
            maxAmountOro,
            minReward,
            extraRewardPerLevel,
            maxRewardLevel,
            referralBonusBps,
            miningInterval,
            streakWindow,
            streakBonusBps,
            worldId,
            APP_ID,
            actionId
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        proxyAddress = address(proxy);
        console.log("DiamanteMineV1_2 proxy deployed to:", proxyAddress);

        vm.stopBroadcast();
    }
}
