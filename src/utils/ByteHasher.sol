// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library ByteHasher {
    function hashToField(bytes memory data) internal pure returns (uint256) {
        return uint256(keccak256(data)) >> 8;
    }
}
