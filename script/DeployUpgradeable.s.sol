// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";
import { IWorldID } from "../src/interfaces/IWorldID.sol";
import { ERC20Mock } from "../tests/mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployUpgradeableDiamanteMine is Script {
    function run() external returns (address) {
        vm.startBroadcast();

        // Deploy mock tokens
        ERC20Mock diamante = new ERC20Mock("T-Diamante", "T-DIAMANTE");
        ERC20Mock oro = new ERC20Mock("T-Oro", "T-ORO");
        console.log("DIAMANTE (mock) deployed to:", address(diamante));
        console.log("ORO (mock) deployed to:", address(oro));

        // Deploy implementation
        DiamanteMineV1 implementation = new DiamanteMineV1();
        console.log("DiamanteMine implementation deployed to:", address(implementation));

        // Set deployment parameters
        IWorldID worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
        uint256 miningFeeInOro = 1 ether;
        uint256 baseReward = 100 ether;
        uint256 maxBonusReward = 50 ether;
        uint256 referralBonusBps = 500; // 5%
        uint256 miningInterval = 1 days;
        string memory appId = "app_2f15cba47775504177f6fa2729103ad6";
        string memory actionId = "mine";

        // Prepare initialization data
        bytes memory data = abi.encodeWithSelector(
            DiamanteMineV1.initialize.selector,
            msg.sender,
            diamante,
            oro,
            miningFeeInOro,
            baseReward,
            maxBonusReward,
            referralBonusBps,
            miningInterval,
            worldId,
            appId,
            actionId
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("DiamanteMine proxy deployed to:", address(proxy));

        // Fund the DiamanteMine contract with rewards
        uint256 initialFunding = 1_000_000 ether;
        diamante.mint(address(proxy), initialFunding);

        console.log("Funded DiamanteMine with %s DIAMANTE", initialFunding / 1e18);

        vm.stopBroadcast();

        return address(proxy);
    }
}
