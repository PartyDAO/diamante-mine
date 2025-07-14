// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { DiamanteMineV1 } from "../../src/DiamanteMineV1.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

contract MockDiamanteMineV2 is DiamanteMineV1 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ISignatureTransfer _permit2) DiamanteMineV1(_permit2) {
        _disableInitializers();
    }

    function VERSION() public pure override returns (string memory) {
        return "2.0.0";
    }

    function newV2Function() public pure returns (bool) {
        return true;
    }
}
