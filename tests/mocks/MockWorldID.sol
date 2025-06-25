// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IWorldID } from "src/interfaces/IWorldID.sol";

contract MockWorldID is IWorldID {
    mapping(uint256 => bool) public nullifiers;

    function verifyProof(
        uint256, // root
        uint256, // groupId
        uint256, // signalHash
        uint256 nullifierHash,
        uint256, // externalNullifierHash
        uint256[8] calldata // proof
    )
        external
    {
        require(!nullifiers[nullifierHash], "MockWorldID: Nullifier has already been used");
        nullifiers[nullifierHash] = true;
    }
}
