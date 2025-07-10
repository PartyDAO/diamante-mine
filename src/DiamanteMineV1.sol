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
    /// @param rewardMultiplier The additional reward from multiplying by ORO amount.
    /// @param referralBonusAmount The referral bonus amount.
    /// @param hasReferralBonus A boolean indicating if a referral bonus was given.
    /// @param amountMined The amount of ORO the user mined with.
    event FinishedMining(
        address indexed user,
        address indexed remindedUser,
        uint256 indexed nullifierHash,
        uint256 totalReward,
        uint256 baseReward,
        uint256 rewardMultiplier,
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

    /// @notice Thrown when trying to set maxRewardLevel to zero.
    error MaxRewardLevelCannotBeZero();

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

        require(_minAmountOro <= _maxAmountOro, MinAmountExceedsMaxAmount());
        require(_maxRewardLevel > 0, MaxRewardLevelCannotBeZero());

        EXTERNAL_NULLIFIER = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
        DIAMANTE = _diamante;
        ORO = _oro;

        minAmountOro = _minAmountOro;
        maxAmountOro = _maxAmountOro;
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
        // Max Mining Reward = Max Base Reward * Max ORO Amount / 1e18 (treat ORO as whole tokens)
        uint256 maxMiningReward = (maxBaseReward() * maxAmountOro) / 1e18;
        // Max Total Reward = Max Mining Reward * (1 + Referral Bonus %)
        return (maxMiningReward * (MAX_BPS + referralBonusBps)) / MAX_BPS;
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
    /// @param args ABI-encoded `(address userToRemind, uint256 amount)`.
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
    {
        // Decode mining arguments
        (address userToRemind, uint256 amount) = _decodeMiningArgs(args);

        require(lastMinedAt[nullifierHash] == 0, AlreadyMining());
        require(amount >= minAmountOro && amount <= maxAmountOro, InvalidOroAmount(amount, minAmountOro, maxAmountOro));
        require(DIAMANTE.balanceOf(address(this)) >= maxReward() * (activeMiners + 1), InsufficientBalanceForReward());

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
        if (remindedUser != address(0)) {
            uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
            uint256 remindedUserStartTime = lastMinedAt[remindedNullifierHash];
            if (
                remindedUserStartTime > startedAt && remindedUserStartTime - startedAt < miningInterval
                    && remindedUser != msg.sender
            ) {
                referralBonusAmount = (multipliedReward * referralBonusBps) / MAX_BPS;
                hasReferralBonus = true;
            }
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

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ADMIN
    //////////////////////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }

    /// @notice Sets the minimum mining amount in ORO tokens.
    /// @param newAmount The new minimum mining amount.
    function setMinAmountOro(uint256 newAmount) external onlyOwner {
        require(newAmount <= maxAmountOro, MinAmountExceedsMaxAmount());
        minAmountOro = newAmount;
    }

    /// @notice Sets the maximum mining amount in ORO tokens.
    /// @param newAmount The new maximum mining amount.
    function setMaxAmountOro(uint256 newAmount) external onlyOwner {
        require(newAmount >= minAmountOro, MinAmountExceedsMaxAmount());
        maxAmountOro = newAmount;
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
        require(newMaxRewardLevel > 0, MaxRewardLevelCannotBeZero());
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

    /*//////////////////////////////////////////////////////////////////////////////
    //                                   HELPERS
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Encodes mining arguments for use with startMining function.
    /// @param referrer The address of the user to refer (can be address(0) for no referral).
    /// @param amount The amount of ORO to use for mining.
    /// @return Encoded mining arguments as bytes.
    function encodeMiningArgs(address referrer, uint256 amount) external pure returns (bytes memory) {
        return abi.encode(referrer, amount);
    }

    /// @notice Decodes mining arguments from bytes.
    /// @param args The encoded mining arguments.
    /// @return referrer The referrer address.
    /// @return amount The ORO amount.
    function _decodeMiningArgs(bytes calldata args) internal pure returns (address referrer, uint256 amount) {
        if (args.length == 0) {
            return (address(0), 0);
        }

        return abi.decode(args, (address, uint256));
    }
}
