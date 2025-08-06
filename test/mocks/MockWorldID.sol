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
        // This mock allows nullifier reuse for features that require a user to mine
        // multiple times in a row, like streaks. The DiamanteMineV1_2 contract
        // contains the necessary logic to prevent a user from starting a new mining
        // session while another is already in progress.
        nullifiers[nullifierHash] = true;
    }
}
