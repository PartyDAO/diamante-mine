// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ByteHasher } from "./utils/ByteHasher.sol";
import { IWorldID } from "./interfaces/IWorldID.sol";
import { Permit2Helper, Permit2, ISignatureTransfer } from "./utils/Permit2Helper.sol";

// solhint-disable-next-line contract-name-capwords
contract DiamanteMineV1_2 is Initializable, UUPSUpgradeable, OwnableUpgradeable, Permit2Helper {
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

    /// @notice Emitted when a streak bonus is awarded.
    /// @param user The address of the user who received the bonus.
    /// @param nullifierHash The nullifier hash of the user's World ID proof.
    /// @param streakBonusAmount The amount of the streak bonus.
    /// @param currentStreak The user's current streak count.
    event StreakBonusAwarded(
        address indexed user, uint256 indexed nullifierHash, uint256 streakBonusAmount, uint256 currentStreak
    );

    /// @notice Emitted when the contract is initialized.
    /// @param initialOwner The initial owner of the contract.
    /// @param diamante The address of the DIAMANTE token.
    /// @param oro The address of the ORO token.
    /// @param minAmountOro The minimum amount in ORO to start mining.
    /// @param maxAmountOro The maximum amount in ORO to start mining.
    /// @param minReward The minimum reward for mining.
    /// @param extraRewardPerLevel The extra reward per level.
    /// @param maxRewardLevel The maximum reward level.
    /// @param referralBonusBps The referral bonus in basis points.
    /// @param miningInterval The mining interval duration in seconds.
    /// @param streakWindow The duration after which a mining streak is considered broken.
    /// @param streakBonus The bonus for maintaining a mining streak.
    /// @param worldId The address of the World ID contract.
    /// @param appId The World ID application ID.
    /// @param actionId The World ID action ID.
    event Initialized(
        address initialOwner,
        address diamante,
        address oro,
        uint256 minAmountOro,
        uint256 maxAmountOro,
        uint256 minReward,
        uint256 extraRewardPerLevel,
        uint256 maxRewardLevel,
        uint256 referralBonusBps,
        uint256 miningInterval,
        uint256 streakWindow,
        uint256 streakBonus,
        address worldId,
        string appId,
        string actionId
    );

    /// @notice Emitted when the contract is migrated to V1.2.
    // solhint-disable-next-line event-name-capwords
    event MigratedToV1_2(uint256 activeOroMining);

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ERRORS
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the contract is already initialized.
    error AlreadyMigratedToV1_2();

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

    /// @notice Thrown when a user tries to remind themself.
    error CannotRemindSelf();

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    STATE
    //////////////////////////////////////////////////////////////////////////////*/

    uint256 private constant MAX_BPS = 10_000;

    /// @notice The safe limit percentage in basis points to apply to required balance calculations.
    /// @dev This allows for a more conservative estimate than worst-case scenario.
    uint256 private constant SAFE_LIMIT_PERCENTAGE_BPS = 6500; // 65%

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

    /// @notice The total amount of ORO all active users are currently mining with.
    uint256 public activeOroMining;

    /// @notice The duration after which a mining streak is considered broken.
    uint40 public streakWindow;
    /// @notice The bonus for maintaining a mining streak.
    uint256 public streakBonus;

    /// @notice Maps a nullifier hash to the timestamp of the last successful mine.
    mapping(uint256 nullifierHash => uint256 timestamp) public lastFinishedMiningAt;
    /// @notice Maps a user's address to their current mining streak.
    mapping(address userAddress => uint256 numOfConsecutiveMines) public userStreak;

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
    /// @param _streakWindow The duration after which a mining streak is considered broken.
    /// @param _streakBonus The bonus for maintaining a mining streak.
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
        uint40 _streakWindow,
        uint256 _streakBonus,
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
        streakWindow = _streakWindow;
        WORLD_ID = _worldId;
        streakBonus = _streakBonus;

        emit Initialized(
            _initialOwner,
            address(_diamante),
            address(_oro),
            _minAmountOro,
            _maxAmountOro,
            _minReward,
            _extraRewardPerLevel,
            _maxRewardLevel,
            _referralBonusBps,
            _miningInterval,
            _streakWindow,
            _streakBonus,
            address(_worldId),
            _appId,
            _actionId
        );
    }

    /// @notice Migrates the contract from V1.1 to V1.2.
    function migrateToV1_2() external onlyOwner {
        require(activeOroMining == 0, AlreadyMigratedToV1_2());
        activeOroMining = activeMiners * 1e18;
        emit MigratedToV1_2(activeOroMining);
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    VIEW
    //////////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the contract version.
    /// @return The contract version string.
    function VERSION() external pure virtual returns (string memory) {
        return "1.2.1";
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

        // Max Total Reward = (Max Mining Reward + Streak Bonus) * (1 + Referral Bonus %)
        return ((maxMiningReward + streakBonus) * (MAX_BPS + referralBonusBps)) / MAX_BPS;
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

    /// @notice Checks if a user is eligible to claim a referral bonus.
    /// @dev This is a helper function for the front-end to determine bonus
    ///      eligibility before calling finishMining.
    /// @param user The address of the user to check.
    /// @return canClaim Whether the user can claim a referral bonus.
    function isEligibleForReferralBonus(address user) public view returns (bool canClaim) {
        uint256 nullifierHash = addressToNullifierHash[user];
        uint256 startedAt = lastMinedAt[nullifierHash];

        // To claim a bonus, the user must be currently mining.
        if (startedAt == 0) {
            return false;
        }

        address remindedUser = lastRemindedAddress[nullifierHash];

        // A user must have been reminded to be eligible for the bonus.
        if (remindedUser == address(0)) {
            return false;
        }

        // Users cannot refer themselves.
        if (remindedUser == user) {
            return false;
        }

        uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
        uint256 remindedUserStartTime = lastMinedAt[remindedNullifierHash];

        // The reminded user must have started mining after the referrer and within the mining interval.
        return remindedUserStartTime > startedAt && remindedUserStartTime - startedAt < miningInterval;
    }

    /// @notice Calculates the potential reward range for a given ORO amount.
    /// @dev This function provides the minimum and maximum possible rewards based on
    ///      the current contract parameters, ignoring referral bonuses for simplicity.
    /// @param oroAmount The amount of ORO to calculate rewards for.
    /// @return minTotalReward The minimum possible reward.
    /// @return maxTotalReward The maximum possible reward.
    function calculateRewardRangeForAmount(uint256 oroAmount)
        public
        view
        returns (uint256 minTotalReward, uint256 maxTotalReward)
    {
        // Validate ORO amount is within acceptable range
        if (oroAmount < minAmountOro || oroAmount > maxAmountOro) {
            return (0, 0);
        }

        // Calculate minimum reward (when there are no active miners, rewardLevel = 0)
        uint256 minBaseRewardAmount = minReward;
        minTotalReward = (minBaseRewardAmount * oroAmount) / 1e18;

        // Calculate maximum reward (when at maximum reward level)
        maxTotalReward = (maxBaseReward() * oroAmount) / 1e18;
    }

    /// @notice Calculates the potential reward range for a user's current mining session.
    /// @param user The address of the user to check.
    /// @return minTotalReward The minimum possible reward for the current session.
    /// @return maxTotalReward The maximum possible reward for the current session.
    function calculateRewardRangeForUser(address user)
        public
        view
        returns (uint256 minTotalReward, uint256 maxTotalReward)
    {
        uint256 nullifierHash = addressToNullifierHash[user];
        uint256 oroAmount = amountOroMinedWith[nullifierHash];

        return calculateRewardRangeForAmount(oroAmount);
    }

    /// @notice Calculates the required DIAMANTE balance to cover all potential mining rewards.
    /// @dev This function is helpful for external alerting tools to notify when balance needs topping off.
    /// @param totalActiveOroMining The total amount of ORO currently being mined.
    /// @return requiredBalance The estimated DIAMANTE balance needed based on safe limit.
    function calculateRequiredBalance(uint256 totalActiveOroMining) public view returns (uint256 requiredBalance) {
        if (totalActiveOroMining == 0) {
            return 0;
        }

        // Calculate the maximum possible reward for the active ORO amount.
        uint256 maxPossibleReward = (maxBaseReward() * totalActiveOroMining) / 1e18;

        // Factor in potential referral bonuses assuming 10% of users earn referral bonus
        // maxPossibleRewardWithBonus = maxPossibleReward * (1 + 0.1 * referralBonus%)
        uint256 maxPossibleRewardWithBonus = (maxPossibleReward * (MAX_BPS + (referralBonusBps / 10))) / MAX_BPS;

        // Apply safe limit percentage to avoid over-reserving capital
        // requiredBalance = maxPossibleRewardWithBonus * safeLimitPercentage
        requiredBalance = (maxPossibleRewardWithBonus * SAFE_LIMIT_PERCENTAGE_BPS) / MAX_BPS;

        return requiredBalance;
    }

    /// @notice Calculates the timestamp when a user's streak will end.
    /// @param user The address of the user.
    /// @return The timestamp of when the streak will end.
    function calculateStreakEndTime(address user) public view returns (uint256) {
        uint256 nullifierHash = addressToNullifierHash[user];
        uint256 lastFinished = lastFinishedMiningAt[nullifierHash];
        if (lastFinished == 0) {
            return 0;
        }
        return lastFinished + streakWindow;
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
        activeOroMining += amount;

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
    ///      Streak bonus = base reward * streak level * streak bonus per level bps
    ///      Referral bonus = base reward * referral bonus bps
    ///      Total reward = base reward + referral bonus + streak bonus
    /// @return multipliedReward The amount of DIAMANTE tokens earned from mining, multiplied by ORO amount.
    /// @return referralBonusAmount The amount of DIAMANTE tokens earned as a referral bonus.
    /// @return streakBonusAmount The amount of DIAMANTE tokens earned as a streak bonus.
    /// @return currentStreak The current streak level.
    /// @return hasReferralBonus A boolean indicating if a referral bonus was awarded.
    function finishMining()
        external
        virtual
        returns (
            uint256 multipliedReward,
            uint256 referralBonusAmount,
            uint256 streakBonusAmount,
            uint256 currentStreak,
            bool hasReferralBonus
        )
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

        // Streak bonus logic
        bool isStreakMaintained = lastFinishedMiningAt[nullifierHash] > 0
            && block.timestamp - lastFinishedMiningAt[nullifierHash] <= streakWindow;
        currentStreak = userStreak[msg.sender];
        if (isStreakMaintained) {
            // Streak is maintained
            currentStreak++;
            streakBonusAmount = streakBonus;
            emit StreakBonusAwarded(msg.sender, nullifierHash, streakBonusAmount, currentStreak);
        } else {
            // Streak is broken or new
            currentStreak = 1;
        }
        userStreak[msg.sender] = currentStreak;

        uint256 totalReward = multipliedReward + referralBonusAmount + streakBonusAmount;

        if (activeMiners != 0) activeMiners--;

        if (activeOroMining >= amountMined) activeOroMining -= amountMined;
        else activeOroMining = 0;

        delete lastMinedAt[nullifierHash];
        delete lastRemindedAddress[nullifierHash];
        delete amountOroMinedWith[nullifierHash];

        lastFinishedMiningAt[nullifierHash] = block.timestamp;

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

        return (multipliedReward, referralBonusAmount, streakBonusAmount, currentStreak, hasReferralBonus);
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

    /// @notice Sets the streak window.
    /// @param newWindow The new streak window in seconds.
    function setStreakWindow(uint40 newWindow) external onlyOwner {
        streakWindow = newWindow;
    }

    /// @notice Sets the streak bonus.
    /// @param newStreakBonus The new streak bonus.
    function setStreakBonus(uint256 newStreakBonus) external onlyOwner {
        streakBonus = newStreakBonus;
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
