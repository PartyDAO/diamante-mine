// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IWorldID
/// @dev Interface for the World ID identity protocol.
interface IWorldID {
    /// @dev Verifies a ZK proof and processes the request.
    /// @param root The root of the Merkle tree to use.
    /// @param groupId The ID of the group the user is a member of.
    /// @param signalHash The hash of the signal the user is sending.
    /// @param nullifierHash The nullifier hash for this proof, which prevents double-spending.
    /// @param externalNullifierHash The external nullifier hash for this proof, which scopes proofs to a particular
    /// action.
    /// @param proof The ZK proof that demonstrates the claimer is a member of the group and is sending the correct
    /// signal.
    /// @notice This function will revert if the proof is invalid.
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    )
        external;
}
