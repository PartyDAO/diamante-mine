// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { ByteHasher } from "./utils/ByteHasher.sol";
import { IWorldID } from "./interfaces/IWorldID.sol";

contract DiamanteMine is Ownable {
    using ByteHasher for bytes;

    IERC20 public diamanteToken;

    uint256 internal constant GROUP_ID = 1;
    IWorldID internal immutable WORLD_ID;
    uint256 internal immutable EXTERNAL_NULLIFIER;

    mapping(uint256 => uint256) public userToLastMiningTimestamp;
    mapping(uint256 => address) public userToLastRemindedAddress;
    mapping(address => uint256) public addressToNullifierHash;

    uint256 constant MINING_INTERVAL = 24 hours;

    constructor(address _diamanteToken, IWorldID _worldId, string memory _appId, string memory _actionId) {
        diamanteToken = IERC20(_diamanteToken);
        WORLD_ID = _worldId;
        EXTERNAL_NULLIFIER = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
    }

    function startMining(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        uint256 userToRemind
    )
        external
    {
        // Check if enough time has passed since last mining session
        if (userToLastMiningTimestamp[nullifierHash] != 0) {
            require(
                block.timestamp - userToLastMiningTimestamp[nullifierHash] >= MINING_INTERVAL,
                "Must wait 24 hours between mining sessions"
            );
        }

        // Verify proof of personhood
        WORLD_ID.verifyProof(
            root, GROUP_ID, abi.encodePacked(msg.sender).hashToField(), nullifierHash, EXTERNAL_NULLIFIER, proof
        );

        userToLastMiningTimestamp[nullifierHash] = block.timestamp;
        // This is a bit janky but when the user starts mining, i'm associating their nullifier hash with their address.
        // This is so that when they finish mining, they don't have to submit another proof.
        addressToNullifierHash[msg.sender] = nullifierHash;

        if (userToRemind != 0) {
            userToLastRemindedAddress[nullifierHash] = userToRemind;
        }
    }

    function finishMining() external {
        uint256 nullifierHash = addressToNullifierHash[msg.sender];
        require(userToLastMiningTimestamp[nullifierHash] > 0, "Must start mining first");
        require(block.timestamp >= userToLastMiningTimestamp[nullifierHash] + MINING_INTERVAL, "Must wait 24 hours");

        // Calculate reward based on block.timestamp % 7 (maps 0-6 to 0.1-1.0 DIAMANTE)
        uint256 timeModulo = block.timestamp % 7;
        uint256 rewardAmount = (1 * 10 ** 17) + (timeModulo * 15 * 10 ** 16); // 0.1 + (0-6 * 0.15)

        // Check referral bonus
        uint256 remindedUser = userToLastRemindedAddress[nullifierHash];
        if (remindedUser != 0) {
            uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
            uint256 remindedUserStartTime = userToLastMiningTimestamp[remindedNullifierHash];
            // If reminded user started mining within 24 hours after this user started
            if (
                remindedUserStartTime > userToLastMiningTimestamp[nullifierHash]
                    && remindedUserStartTime - userToLastMiningTimestamp[nullifierHash] < MINING_INTERVAL
                    && remindedUser != msg.sender
            ) {
                rewardAmount = rewardAmount * 11 / 10; // 1.1x multiplier
            }
        }

        // Transfer reward from contract to user
        require(diamanteToken.transfer(msg.sender, rewardAmount), "Transfer failed");

        // Reset mining time to allow next mining session
        userToLastMiningTimestamp[nullifierHash] = 0;
        userToLastRemindedAddress[nullifierHash] = address(0);
        addressToNullifierHash[msg.sender] = 0;
    }

    // Owner function to deposit DIAMANTE tokens into the contract
    function depositTokens(uint256 amount) external onlyOwner {
        require(diamanteToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    // Owner function to withdraw tokens if needed
    function withdrawTokens(uint256 amount) external onlyOwner {
        require(diamanteToken.transfer(msg.sender, amount), "Transfer failed");
    }

    // View function to check contract's DIAMANTE balance
    function getContractBalance() external view returns (uint256) {
        return diamanteToken.balanceOf(address(this));
    }
}
