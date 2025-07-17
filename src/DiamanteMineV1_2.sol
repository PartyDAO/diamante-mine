// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.30;

import { DiamanteMineV1_1 } from "./DiamanteMineV1_1.sol";

contract DiamanteMineV1_2 is DiamanteMineV1_1 {
    /*//////////////////////////////////////////////////////////////////////////////
    //                                  STATE
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice The total amount of ORO all active users are currently mining with.
    uint256 public activeOroMining;

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    VIEW
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the contract version.
    /// @return The contract version string.
    function VERSION() external pure override returns (string memory) {
        return "1.2.0";
    }

    /// @notice Calculates the required DIAMANTE balance to cover all potential mining rewards.
    /// @dev This function is helpful for external alerting tools to notify when balance needs topping off.
    /// @param totalActiveOroMining The total amount of ORO currently being mined.
    /// @return requiredBalance The minimum DIAMANTE balance needed to cover all potential payouts.
    function calculateRequiredBalance(uint256 totalActiveOroMining) public view returns (uint256 requiredBalance) {
        if (totalActiveOroMining == 0) {
            return 0;
        }

        // Get the maximum possible reward for the active ORO amount
        (, uint256 maxPossibleReward) = calculateRewardRangeForAmount(totalActiveOroMining);

        // TODO: Not sure if this is too aggressive, but if we wanted to be conservative...
        // Factor in potential referral bonuses (assume maximum possible bonus)
        // maxPossibleRewardWithBonus = maxPossibleReward * (1 + referralBonus %)
        uint256 maxPossibleRewardWithBonus = (maxPossibleReward * (MAX_BPS + referralBonusBps)) / MAX_BPS;

        return maxPossibleRewardWithBonus;
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                     CORE
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Starts the mining process for the caller.
    /// @dev Requires a valid World ID proof. The user must pay a fee in ORO tokens.
    /// @param args Encoded mining arguments containing referrer address and ORO amount.
    /// @param root The root of the Merkle tree of World ID identities.
    /// @param nullifierHash A unique identifier for the user's proof.
    /// @param proof The zero-knowledge proof of personhood.
    /// @param permit A Permit2 struct for approving the ORO token transfer.
    function startMining(
        bytes calldata args,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        Permit2 memory permit
    )
        external
        virtual
    {
        // Decode mining arguments
        (address userToRemind, uint256 amount) = _decodeMiningArgs(args);

        require(userToRemind != msg.sender, CannotRemindSelf());

        require(lastMinedAt[nullifierHash] == 0, AlreadyMining());
        require(amount >= minAmountOro && amount <= maxAmountOro, InvalidOroAmount(amount, minAmountOro, maxAmountOro));
        require(
            DIAMANTE.balanceOf(address(this)) >= calculateRequiredBalance(activeOroMining + amount),
            InsufficientBalanceForReward()
        );

        // Verify proof of personhood before any state changes
        WORLD_ID.verifyProof(
            root, GROUP_ID, abi.encodePacked(msg.sender).hashToField(), nullifierHash, EXTERNAL_NULLIFIER, proof
        );

        activeMiners++;

        lastMinedAt[nullifierHash] = block.timestamp;
        amountOroMinedWith[nullifierHash] = amount;
        addressToNullifierHash[msg.sender] = nullifierHash;

        // Store referral information
        if (userToRemind != address(0)) {
            lastRemindedAddress[nullifierHash] = userToRemind;
        }

        PERMIT2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({ token: address(ORO), amount: amount }),
                nonce: permit.nonce,
                deadline: permit.deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({ to: address(this), requestedAmount: amount }),
            msg.sender,
            permit.signature
        );

        emit StartedMining(msg.sender, userToRemind, nullifierHash, amount);
    }

    /// @notice Finishes the mining process and claims the reward.
    /// @dev The user must have been mining for at least `miningInterval`.
    ///      Reward = base reward * ORO amount (2 ORO = 2x reward, 3 ORO = 3x reward, etc.)
    /// @return multipliedReward The amount of DIAMANTE tokens earned from mining, multiplied by ORO amount.
    /// @return referralBonusAmount The amount of DIAMANTE tokens earned as a referral bonus.
    /// @return hasReferralBonus A boolean indicating if a referral bonus was awarded.
    function finishMining()
        external
        virtual
        returns (uint256 multipliedReward, uint256 referralBonusAmount, bool hasReferralBonus)
    {
        uint256 nullifierHash = addressToNullifierHash[msg.sender];
        uint256 startedAt = lastMinedAt[nullifierHash];
        require(startedAt != 0, MiningNotStarted());
        require(block.timestamp >= startedAt + miningInterval, MiningIntervalNotElapsed());

        // Calculate reward
        // NOTE: Unlikely to happen, but activeMiners can be 0 here if this is the last miner.
        // When the last miner finishes, activeMiners will be 1, resulting in a rewardLevel of 0.
        // With this change, `maxRewardLevel` represents the total number of reward tiers.
        // If maxRewardLevel is 10, the possible levels are 0 through 9.
        uint256 rewardLevel = activeMiners == 0 ? 0 : (activeMiners - 1) % maxRewardLevel;
        uint256 levelBonus = extraRewardPerLevel * rewardLevel;
        uint256 baseReward = minReward + levelBonus;

        uint256 amountMined = amountOroMinedWith[nullifierHash];
        // Directly multiply base reward by ORO amount (2 ORO = 2x reward, 3 ORO = 3x reward, etc.)
        // Divide by 1e18 to treat ORO as whole tokens rather than wei
        multipliedReward = (baseReward * amountMined) / 1e18;

        // Check for and apply referral bonus
        address remindedUser = lastRemindedAddress[nullifierHash];
        if (isEligibleForReferralBonus(msg.sender)) {
            referralBonusAmount = (multipliedReward * referralBonusBps) / MAX_BPS;
            hasReferralBonus = true;
        }

        uint256 totalReward = multipliedReward + referralBonusAmount;

        if (activeMiners != 0) activeMiners--;

        delete lastMinedAt[nullifierHash];
        delete lastRemindedAddress[nullifierHash];
        delete addressToNullifierHash[msg.sender];
        delete amountOroMinedWith[nullifierHash];

        DIAMANTE.safeTransfer(msg.sender, totalReward);

        emit FinishedMining(
            msg.sender,
            remindedUser,
            nullifierHash,
            totalReward,
            baseReward,
            multipliedReward - baseReward, // rewardMultiplier is the additional reward from ORO multiplier
            referralBonusAmount,
            hasReferralBonus,
            amountMined
        );
    }
}
