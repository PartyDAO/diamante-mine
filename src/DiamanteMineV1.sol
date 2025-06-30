// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ByteHasher } from "./utils/ByteHasher.sol";
import { IWorldID } from "./interfaces/IWorldID.sol";
import { Permit2Helper, Permit2, ISignatureTransfer } from "./utils/Permit2Helper.sol";

contract DiamanteMineV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, Permit2Helper {
    using ByteHasher for bytes;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    EVENTS
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user starts mining.
    /// @param user The address of the user who started mining.
    /// @param remindedUser The address of the user who was reminded to mine.
    /// @param nullifierHash The nullifier hash of the user's World ID proof.
    /// @param amount The amount of ORO the user mined with.
    event StartedMining(
        address indexed user, address indexed remindedUser, uint256 indexed nullifierHash, uint256 amount
    );

    /// @notice Emitted when a user finishes mining and claims their reward.
    /// @param user The address of the user who finished mining.
    /// @param remindedUser The address of the user who was reminded.
    /// @param nullifierHash The nullifier hash of the user's World ID proof.
    /// @param totalReward The total reward amount (mining reward + referral bonus).
    /// @param baseReward The base mining reward amount.
    /// @param rewardBoost The boost to the reward from mining with extra ORO.
    /// @param referralBonusAmount The referral bonus amount.
    /// @param hasReferralBonus A boolean indicating if a referral bonus was given.
    /// @param amountMined The amount of ORO the user mined with.
    event FinishedMining(
        address indexed user,
        address indexed remindedUser,
        uint256 indexed nullifierHash,
        uint256 totalReward,
        uint256 baseReward,
        uint256 rewardBoost,
        uint256 referralBonusAmount,
        bool hasReferralBonus,
        uint256 amountMined
    );

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ERRORS
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a user tries to finish mining before the mining interval has elapsed.
    error MiningIntervalNotElapsed();

    /// @notice Thrown when the contract does not have enough DIAMANTE tokens to pay the reward.
    error InsufficientBalanceForReward();

    /// @notice Thrown when a user tries to finish mining without having started.
    error MiningNotStarted();

    /// @notice Thrown when a user tries to start mining while already mining.
    error AlreadyMining();

    /// @notice Thrown when the provided ORO amount is not within the allowed range.
    error InvalidOroAmount(uint256 amount, uint256 min, uint256 max);

    /// @notice Thrown when setting min amount higher than max amount.
    error MinAmountExceedsMaxAmount();

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    STATE
    //////////////////////////////////////////////////////////////////////////////*/

    uint256 private constant MAX_BPS = 10_000;

    /// @notice The DIAMANTE token contract. This is the reward token.
    IERC20 public DIAMANTE;
    /// @notice The ORO token contract. This token is used to pay the mining fee.
    IERC20 public ORO;
    /// @notice The World ID contract interface.
    IWorldID public WORLD_ID;
    /// @notice The external nullifier for World ID, constructed from the app and action IDs.
    uint256 public EXTERNAL_NULLIFIER;
    /// @notice The World ID group ID.
    uint256 public constant GROUP_ID = 1;

    /// @notice The duration a user must wait before they can finish mining.
    uint256 public miningInterval;
    /// @notice The minimum amount in ORO tokens required to start mining.
    uint256 public minAmountOro;
    /// @notice The maximum amount in ORO tokens allowed to start mining.
    uint256 public maxAmountOro;
    /// @notice The maximum reward boost a user can receive for mining with more ORO, in BPS.
    uint256 public maxRewardBoostBps;
    /// @notice The minimum reward a user can receive for mining.
    uint256 public minReward;
    /// @notice The extra reward a user can receive for each level. The level is based on the number of active miners.
    uint256 public extraRewardPerLevel;
    /// @notice The referral bonus in basis points.
    uint256 public referralBonusBps;
    /// @notice The maximum reward level.
    uint256 public maxRewardLevel;

    /// @notice Maps a nullifier hash to the timestamp when the user last started mining.
    mapping(uint256 nullifierHash => uint256 timestamp) public lastMinedAt;
    /// @notice Maps a nullifier hash to the address of the user they reminded.
    mapping(uint256 nullifierHash => address userAddress) public lastRemindedAddress;
    /// @notice Maps a nullifier hash to the amount of ORO the user is mining with.
    mapping(uint256 nullifierHash => uint256 amount) public amountOroMinedWith;
    /// @notice Maps a user's address to their World ID nullifier hash.
    mapping(address userAddress => uint256 nullifierHash) public addressToNullifierHash;

    /// @notice The number of users currently mining.
    uint256 public activeMiners;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ISignatureTransfer _permit2) Permit2Helper(_permit2) {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                  INITIALIZE
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract.
    /// @param _initialOwner The initial owner of the contract.
    /// @param _diamante The address of the DIAMANTE token.
    /// @param _oro The address of the ORO token.
    /// @param _minAmountOro The minimum amount in ORO to start mining.
    /// @param _maxAmountOro The maximum amount in ORO to start mining.
    /// @param _maxRewardBoostBps The maximum reward boost in BPS.
    /// @param _minReward The minimum reward for mining.
    /// @param _extraRewardPerLevel The extra reward per level.
    /// @param _maxRewardLevel The maximum reward level.
    /// @param _referralBonusBps The referral bonus in basis points.
    /// @param _miningInterval The mining interval duration in seconds.
    /// @param _worldId The address of the World ID contract.
    /// @param _appId The World ID application ID.
    /// @param _actionId The World ID action ID.
    function initialize(
        address _initialOwner,
        IERC20 _diamante,
        IERC20 _oro,
        uint256 _minAmountOro,
        uint256 _maxAmountOro,
        uint256 _maxRewardBoostBps,
        uint256 _minReward,
        uint256 _extraRewardPerLevel,
        uint256 _maxRewardLevel,
        uint256 _referralBonusBps,
        uint256 _miningInterval,
        IWorldID _worldId,
        string memory _appId,
        string memory _actionId
    )
        public
        initializer
    {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        if (_minAmountOro > _maxAmountOro) revert MinAmountExceedsMaxAmount();

        EXTERNAL_NULLIFIER = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
        DIAMANTE = _diamante;
        ORO = _oro;

        minAmountOro = _minAmountOro;
        maxAmountOro = _maxAmountOro;
        maxRewardBoostBps = _maxRewardBoostBps;
        minReward = _minReward;
        extraRewardPerLevel = _extraRewardPerLevel;
        maxRewardLevel = _maxRewardLevel;
        referralBonusBps = _referralBonusBps;
        miningInterval = _miningInterval;
        WORLD_ID = _worldId;
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    VIEW
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the contract version.
    /// @return The contract version string.
    function VERSION() external pure virtual returns (string memory) {
        return "1.1.0";
    }

    /// @notice Calculates the maximum possible bonus reward.
    /// @return The maximum bonus reward amount.
    function maxBonusReward() public view returns (uint256) {
        // The max bonus assuming highest possible level (maxRewardLevel)
        return extraRewardPerLevel * maxRewardLevel;
    }

    /// @notice Calculates the maximum base reward (minimum reward + maximum bonus).
    /// @return The maximum base reward amount.
    function maxBaseReward() public view returns (uint256) {
        return minReward + maxBonusReward();
    }

    /// @notice Calculates the maximum possible total reward including referral bonus.
    /// @return The maximum total reward amount.
    function maxReward() public view returns (uint256) {
        // Boosted Max Reward = Max Base Reward * (1 + Max Boost %)
        uint256 boosted = (maxBaseReward() * (MAX_BPS + maxRewardBoostBps)) / MAX_BPS;
        // Total Max Reward = Boosted Max Reward * (1 + Referral Bonus %)
        return (boosted * (MAX_BPS + referralBonusBps)) / MAX_BPS;
    }

    /// @notice Represents the mining state of a user.
    enum MiningState {
        NotMining,
        Mining,
        ReadyToFinish
    }

    /// @notice Gets the current mining state for a given user.
    /// @param user The address of the user.
    /// @return The mining state of the user.
    function getUserMiningState(address user) public view returns (MiningState) {
        uint256 nullifierHash = addressToNullifierHash[user];
        uint256 startedAt = lastMinedAt[nullifierHash];
        if (startedAt == 0) {
            return MiningState.NotMining;
        }

        if (block.timestamp >= startedAt + miningInterval) {
            return MiningState.ReadyToFinish;
        }

        return MiningState.Mining;
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                     CORE
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Starts the mining process for the caller.
    /// @dev Requires a valid World ID proof. The user must pay a fee in ORO tokens.
    /// @param root The root of the Merkle tree of World ID identities.
    /// @param nullifierHash A unique identifier for the user's proof.
    /// @param proof The zero-knowledge proof of personhood.
    /// @param userToRemind The address of a user to remind, who might provide a referral bonus.
    /// @param amount The amount of ORO to use for mining.
    /// @param permit A Permit2 struct for approving the ORO token transfer.
    function startMining(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        address userToRemind,
        uint256 amount,
        Permit2 memory permit
    )
        external
    {
        if (lastMinedAt[nullifierHash] != 0) revert AlreadyMining();
        if (amount < minAmountOro || amount > maxAmountOro) {
            revert InvalidOroAmount(amount, minAmountOro, maxAmountOro);
        }
        if (DIAMANTE.balanceOf(address(this)) < maxReward() * (activeMiners + 1)) {
            revert InsufficientBalanceForReward();
        }

        // Verify proof of personhood before any state changes
        WORLD_ID.verifyProof(
            root, GROUP_ID, abi.encodePacked(msg.sender).hashToField(), nullifierHash, EXTERNAL_NULLIFIER, proof
        );

        activeMiners++;

        lastMinedAt[nullifierHash] = block.timestamp;
        amountOroMinedWith[nullifierHash] = amount;
        addressToNullifierHash[msg.sender] = nullifierHash;

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
    /// @return boostedReward The amount of DIAMANTE tokens earned from mining, including boost.
    /// @return referralBonusAmount The amount of DIAMANTE tokens earned as a referral bonus.
    /// @return hasReferralBonus A boolean indicating if a referral bonus was awarded.
    function finishMining()
        external
        returns (uint256 boostedReward, uint256 referralBonusAmount, bool hasReferralBonus)
    {
        uint256 nullifierHash = addressToNullifierHash[msg.sender];
        uint256 startedAt = lastMinedAt[nullifierHash];
        if (startedAt == 0) revert MiningNotStarted();
        if (block.timestamp < startedAt + miningInterval) revert MiningIntervalNotElapsed();

        // Calculate reward
        // NOTE: Unlikely to happen, but activeMiners can be 0 here if this is the last miner.
        // When the last miner finishes, activeMiners will be 1, resulting in a rewardLevel of 0.
        uint256 rewardLevel = activeMiners == 0 ? 0 : (activeMiners - 1) % (maxRewardLevel + 1);
        uint256 levelBonus = extraRewardPerLevel * rewardLevel;
        uint256 baseReward = minReward + levelBonus;

        uint256 amountMined = amountOroMinedWith[nullifierHash];
        uint256 boostBps = 0;
        if (maxAmountOro > minAmountOro) {
            // The reward boost is a percentage of the base reward, determined by how much
            // ORO the user mines with, scaling linearly from 0% to the max boost percentage:
            // Boost % = (Amount Mined - Min Amount) / (Max Amount - Min Amount) * Max Boost %
            uint256 amountInExcess = amountMined - minAmountOro;
            uint256 amountDelta = maxAmountOro - minAmountOro;
            boostBps = (amountInExcess * maxRewardBoostBps) / amountDelta;
        }
        // Reward Boost = Base Reward * Boost %
        uint256 rewardBoost = (baseReward * boostBps) / MAX_BPS;
        boostedReward = baseReward + rewardBoost;

        // Check for and apply referral bonus
        address remindedUser = lastRemindedAddress[nullifierHash];
        if (remindedUser != address(0)) {
            uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
            uint256 remindedUserStartTime = lastMinedAt[remindedNullifierHash];
            if (
                remindedUserStartTime > startedAt && remindedUserStartTime - startedAt < miningInterval
                    && remindedUser != msg.sender
            ) {
                referralBonusAmount = (boostedReward * referralBonusBps) / MAX_BPS;
                hasReferralBonus = true;
            }
        }

        uint256 totalReward = boostedReward + referralBonusAmount;

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
            rewardBoost,
            referralBonusAmount,
            hasReferralBonus,
            amountMined
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ADMIN
    //////////////////////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }

    /// @notice Sets the minimum mining amount in ORO tokens.
    /// @param newAmount The new minimum mining amount.
    function setMinAmountOro(uint256 newAmount) external onlyOwner {
        if (newAmount > maxAmountOro) revert MinAmountExceedsMaxAmount();
        minAmountOro = newAmount;
    }

    /// @notice Sets the maximum mining amount in ORO tokens.
    /// @param newAmount The new maximum mining amount.
    function setMaxAmountOro(uint256 newAmount) external onlyOwner {
        if (newAmount < minAmountOro) revert MinAmountExceedsMaxAmount();
        maxAmountOro = newAmount;
    }

    /// @notice Sets the maximum reward boost in BPS.
    /// @param newRewardBoostBps The new maximum reward boost in BPS.
    function setMaxRewardBoostBps(uint256 newRewardBoostBps) external onlyOwner {
        maxRewardBoostBps = newRewardBoostBps;
    }

    /// @notice Sets the mining interval.
    /// @param newInterval The new mining interval in seconds.
    function setMiningInterval(uint256 newInterval) external onlyOwner {
        miningInterval = newInterval;
    }

    /// @notice Sets the minimum mining reward.
    /// @param newMinReward The new minimum reward.
    function setMinReward(uint256 newMinReward) external onlyOwner {
        minReward = newMinReward;
    }

    /// @notice Sets the extra reward per level.
    /// @param newExtraRewardPerLevel The new extra reward per level.
    function setExtraRewardPerLevel(uint256 newExtraRewardPerLevel) external onlyOwner {
        extraRewardPerLevel = newExtraRewardPerLevel;
    }

    /// @notice Sets the maximum reward level.
    /// @param newMaxRewardLevel The new maximum reward level.
    function setMaxRewardLevel(uint256 newMaxRewardLevel) external onlyOwner {
        maxRewardLevel = newMaxRewardLevel;
    }

    /// @notice Sets the referral bonus in basis points.
    /// @param newReferralBonusBps The new referral bonus in bps.
    function setReferralBonusBps(uint256 newReferralBonusBps) external onlyOwner {
        referralBonusBps = newReferralBonusBps;
    }

    /// @notice Deposits ERC20 tokens into the contract. Can only be called by the owner.
    /// @param token The address of the ERC20 token.
    /// @param amount The amount of tokens to deposit.
    function depositERC20(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraws ERC20 tokens from the contract. Can only be called by the owner.
    /// @param token The address of the ERC20 token.
    /// @param amount The amount of tokens to withdraw.
    function withdrawERC20(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransfer(owner(), amount);
    }
}
