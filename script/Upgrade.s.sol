// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgradeScript is Script {
    DiamanteMineV1 public proxy = DiamanteMineV1(0x707670dBD7bD05b744D428A663BE634bC5E7Da96);

    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function run() external {
        // You'll need to provide the proxy address.
        if (address(proxy) == address(0)) {
            console.log(
                "Please update the proxyAddress in script/Upgrade.s.sol with your deployed DiamanteMineV1 proxy address."
            );
            return;
        }

        vm.startBroadcast();

        // 1. Deploy the new implementation contract.
        DiamanteMineV1 newImplementation = new DiamanteMineV1(PERMIT2);
        console.log("New DiamanteMineV1 implementation deployed to:", address(newImplementation));

        // 2. Upgrade the proxy to the new implementation.
        // The owner of the proxy will be the deployer of the original contract.
        proxy.upgradeToAndCall(address(newImplementation), "");

        console.log("Proxy successfully upgraded to new implementation.");

        vm.stopBroadcast();
    }
}
