// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ByteHasher } from "./utils/ByteHasher.sol";
import { IWorldID } from "./interfaces/IWorldID.sol";

contract DiamanteMineV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using ByteHasher for bytes;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    EVENTS
    //////////////////////////////////////////////////////////////////////////////*/

    event StartedMining(address indexed user, address indexed remindedUser, uint256 indexed nullifierHash);

    event FinishedMining(
        address indexed user,
        address indexed remindedUser,
        uint256 indexed nullifierHash,
        uint256 totalReward,
        uint256 miningReward,
        uint256 referralBonusAmount,
        bool hasReferralBonus
    );

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ERRORS
    //////////////////////////////////////////////////////////////////////////////*/

    error MiningIntervalNotElapsed();
    error InsufficientBalanceForReward();
    error MiningNotStarted();
    error AlreadyMining();

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    STATE
    //////////////////////////////////////////////////////////////////////////////*/

    uint256 private constant MAX_BPS = 10_000;

    IERC20 public DIAMANTE;
    IERC20 public ORO;
    IWorldID internal WORLD_ID;
    uint256 internal EXTERNAL_NULLIFIER;
    uint256 internal constant GROUP_ID = 1;

    uint256 public miningInterval;
    uint256 public miningFeeInOro;
    uint256 public minReward;
    uint256 public extraRewardPerLevel;
    uint256 public referralBonusBps;

    mapping(uint256 nullifierHash => uint256 timestamp) public lastMinedAt;
    mapping(uint256 nullifierHash => address userAddress) public lastRemindedAddress;
    mapping(address userAddress => uint256 nullifierHash) public addressToNullifierHash;

    uint256 public activeMiners;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                  INITIALIZE
    //////////////////////////////////////////////////////////////////////////////*/

    function initialize(
        address _initialOwner,
        IERC20 _diamante,
        IERC20 _oro,
        uint256 _miningFeeInOro,
        uint256 _minReward,
        uint256 _extraRewardPerLevel,
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

        DIAMANTE = _diamante;
        ORO = _oro;
        miningFeeInOro = _miningFeeInOro;
        minReward = _minReward;
        extraRewardPerLevel = _extraRewardPerLevel;
        referralBonusBps = _referralBonusBps;
        miningInterval = _miningInterval;
        WORLD_ID = _worldId;
        EXTERNAL_NULLIFIER = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    VIEW
    //////////////////////////////////////////////////////////////////////////////*/

    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }

    function maxBonusReward() public view returns (uint256) {
        // The max bonus is from the highest possible level (10)
        return extraRewardPerLevel * 10;
    }

    function maxBaseReward() public view returns (uint256) {
        return minReward + maxBonusReward();
    }

    function maxReward() public view returns (uint256) {
        return (maxBaseReward() * (MAX_BPS + referralBonusBps)) / MAX_BPS;
    }

    enum MiningState {
        NotMining,
        Mining,
        ReadyToFinish
    }

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

    function startMining(
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof,
        address userToRemind
    )
        external
    {
        uint256 lastMined = lastMinedAt[nullifierHash];
        require(lastMined == 0, AlreadyMining());
        require(DIAMANTE.balanceOf(address(this)) >= maxReward(), InsufficientBalanceForReward());

        // Verify proof of personhood before any state changes
        WORLD_ID.verifyProof(
            root, GROUP_ID, abi.encodePacked(msg.sender).hashToField(), nullifierHash, EXTERNAL_NULLIFIER, proof
        );

        activeMiners++;

        lastMinedAt[nullifierHash] = block.timestamp;
        addressToNullifierHash[msg.sender] = nullifierHash;

        if (userToRemind != address(0)) {
            lastRemindedAddress[nullifierHash] = userToRemind;
        }

        ORO.safeTransferFrom(msg.sender, address(this), miningFeeInOro);

        emit StartedMining(msg.sender, userToRemind, nullifierHash);
    }

    function finishMining()
        external
        returns (uint256 miningReward, uint256 referralBonusAmount, bool hasReferralBonus)
    {
        uint256 nullifierHash = addressToNullifierHash[msg.sender];
        uint256 startedAt = lastMinedAt[nullifierHash];
        require(startedAt > 0, MiningNotStarted());
        require(block.timestamp >= startedAt + miningInterval, MiningIntervalNotElapsed());

        // Calculate reward
        // NOTE: Unlikely to happen, but activeMiners can be 0 here if this is the last miner.
        // When the last miner finishes, activeMiners will be 1, resulting in a rewardLevel of 0.
        uint256 rewardLevel = activeMiners == 0 ? 0 : (activeMiners - 1) % 11;
        uint256 randomBonus = extraRewardPerLevel * rewardLevel;
        miningReward = minReward + randomBonus;

        // Check for and apply referral bonus
        address remindedUser = lastRemindedAddress[nullifierHash];
        if (remindedUser != address(0)) {
            uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
            uint256 remindedUserStartTime = lastMinedAt[remindedNullifierHash];
            if (
                remindedUserStartTime > startedAt && remindedUserStartTime - startedAt < miningInterval
                    && remindedUser != msg.sender
            ) {
                referralBonusAmount = (miningReward * referralBonusBps) / MAX_BPS;
                hasReferralBonus = true;
            }
        }

        uint256 totalReward = miningReward + referralBonusAmount;

        if (activeMiners != 0) activeMiners--;

        delete lastMinedAt[nullifierHash];
        delete lastRemindedAddress[nullifierHash];
        delete addressToNullifierHash[msg.sender];

        DIAMANTE.safeTransfer(msg.sender, totalReward);

        emit FinishedMining(
            msg.sender, remindedUser, nullifierHash, totalReward, miningReward, referralBonusAmount, hasReferralBonus
        );
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ADMIN
    //////////////////////////////////////////////////////////////////////////////*/

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }

    function setMiningFeeInOro(uint256 newFee) external onlyOwner {
        miningFeeInOro = newFee;
    }

    function setMiningInterval(uint256 newInterval) external onlyOwner {
        miningInterval = newInterval;
    }

    function setMinReward(uint256 newMinReward) external onlyOwner {
        minReward = newMinReward;
    }

    function setExtraRewardPerLevel(uint256 newExtraRewardPerLevel) external onlyOwner {
        extraRewardPerLevel = newExtraRewardPerLevel;
    }

    function setReferralBonusBps(uint256 newReferralBonusBps) external onlyOwner {
        referralBonusBps = newReferralBonusBps;
    }

    function depositERC20(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawERC20(IERC20 token, uint256 amount) external onlyOwner {
        token.safeTransfer(owner(), amount);
    }
}
