// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

struct Permit2 {
    uint256 nonce;
    uint256 deadline;
    bytes signature;
}

contract Permit2Helper {
    ISignatureTransfer public immutable PERMIT2;

    constructor(ISignatureTransfer _permit2) {
        PERMIT2 = _permit2;
    }
}
