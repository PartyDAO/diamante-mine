// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.dev.sol";
import { IWorldID } from "../src/interfaces/IWorldID.sol";
import { ERC20Mock } from "../tests/mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

contract DeployUpgradeableDiamanteMineDev is Script {
    ISignatureTransfer public PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    ERC20Mock public MOCK_DIAMANTE = ERC20Mock(0xFc46DC32F6Adb60d65012f7e943c3f29EB867796);
    ERC20Mock public MOCK_ORO = ERC20Mock(0x27Ef8b2c8d843343243D7FF9445D6F7F283d911b);

    function run() external returns (address[] memory proxies) {
        vm.startBroadcast();

        // Deploy implementation
        DiamanteMineV1 implementation = new DiamanteMineV1(PERMIT2);
        console.log("DiamanteMine implementation deployed to:", address(implementation));

        // Set deployment parameters
        IWorldID worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
        uint256 miningFeeInOro = 1 ether;
        uint256 baseReward = 100 ether;
        uint256 extraRewardPerLevel = 50 ether;
        uint256 maxRewardLevel = 10;
        uint256 referralBonusBps = 500; // 5%
        uint256 miningInterval = 1 days;
        string memory actionId = "mine";

        string[] memory appIds = new string[](2);
        appIds[0] = "app_44080323ee897f20dfbacdd30cedf2a8"; // Marcus
        appIds[1] = "app_2f15cba47775504177f6fa2729103ad6"; // Steve

        proxies = new address[](appIds.length);

        for (uint256 i = 0; i < appIds.length; i++) {
            string memory appId = appIds[i];
            console.log("Deploying DiamanteMine for appId:", appId);

            // Prepare initialization data
            bytes memory data = abi.encodeWithSelector(
                DiamanteMineV1.initialize.selector,
                msg.sender,
                MOCK_DIAMANTE,
                MOCK_ORO,
                miningFeeInOro,
                baseReward,
                extraRewardPerLevel,
                maxRewardLevel,
                referralBonusBps,
                miningInterval,
                worldId,
                appId,
                actionId
            );

            // Deploy proxy
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
            console.log("DiamanteMine proxy deployed to:", address(proxy));
            proxies[i] = address(proxy);

            // Fund the DiamanteMine contract with rewards
            uint256 initialFunding = 1_000_000 ether;
            MOCK_DIAMANTE.mint(address(proxy), initialFunding);

            console.log("Funded DiamanteMine with %s DIAMANTE", initialFunding / 1e18);
        }

        vm.stopBroadcast();
    }
}
