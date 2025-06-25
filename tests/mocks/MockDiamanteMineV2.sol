// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DiamanteMineV1 } from "../../src/DiamanteMineV1.sol";

contract MockDiamanteMineV2 is DiamanteMineV1 {
    function version() public pure override returns (string memory) {
        return "2.0.0";
    }

    function newV2Function() public pure returns (bool) {
        return true;
    }
}
