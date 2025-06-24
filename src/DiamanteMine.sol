// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ByteHasher } from "./utils/ByteHasher.sol";
import { IWorldID } from "./interfaces/IWorldID.sol";

contract DiamanteMine is Ownable {
    using ByteHasher for bytes;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ERRORS
    //////////////////////////////////////////////////////////////////////////////*/

    error MiningIntervalNotElapsed();
    error InsufficientBalanceForReward();
    error MiningNotStarted();

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    STATE
    //////////////////////////////////////////////////////////////////////////////*/

    uint256 private constant MAX_BPS = 10_000;

    IERC20 public immutable DIAMANTE;
    IERC20 public immutable ORO;
    IWorldID internal immutable WORLD_ID;
    uint256 internal immutable EXTERNAL_NULLIFIER;
    uint256 internal constant GROUP_ID = 1;

    uint256 public miningInterval;
    uint256 public miningFeeInOro;
    uint256 public baseReward;
    uint256 public maxBonusReward;
    uint256 public referralBonusBps;

    mapping(uint256 nullifierHash => uint256 timestamp) public lastMinedAt;
    mapping(uint256 nullifierHash => address userAddress) public lastRemindedAddress;
    mapping(address userAddress => uint256 nullifierHash) public addressToNullifierHash;

    /*//////////////////////////////////////////////////////////////////////////////
    //                                  INITIALIZE
    //////////////////////////////////////////////////////////////////////////////*/

    constructor(
        IERC20 _diamante,
        IERC20 _oro,
        uint256 _miningFeeInOro,
        uint256 _baseReward,
        uint256 _maxBonusReward,
        uint256 _referralBonusBps,
        uint256 _miningInterval,
        IWorldID _worldId,
        string memory _appId,
        string memory _actionId
    )
        Ownable(msg.sender)
    {
        DIAMANTE = _diamante;
        ORO = _oro;
        miningFeeInOro = _miningFeeInOro;
        baseReward = _baseReward;
        maxBonusReward = _maxBonusReward;
        referralBonusBps = _referralBonusBps;
        miningInterval = _miningInterval;
        WORLD_ID = _worldId;
        EXTERNAL_NULLIFIER = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    VIEW
    //////////////////////////////////////////////////////////////////////////////*/

    function minReward() public view returns (uint256) {
        return baseReward;
    }

    function maxReward() public view returns (uint256) {
        uint256 maxBaseReward = baseReward + maxBonusReward;
        return (maxBaseReward * (MAX_BPS + referralBonusBps)) / MAX_BPS;
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
        if (lastMinedAt[nullifierHash] != 0) {
            require(block.timestamp - lastMinedAt[nullifierHash] >= miningInterval, MiningIntervalNotElapsed());
        }
        require(DIAMANTE.balanceOf(address(this)) >= maxReward(), InsufficientBalanceForReward());

        // Verify proof of personhood before any state changes
        WORLD_ID.verifyProof(
            root, GROUP_ID, abi.encodePacked(msg.sender).hashToField(), nullifierHash, EXTERNAL_NULLIFIER, proof
        );

        lastMinedAt[nullifierHash] = block.timestamp;
        addressToNullifierHash[msg.sender] = nullifierHash;

        if (userToRemind != address(0)) {
            lastRemindedAddress[nullifierHash] = userToRemind;
        }

        ORO.safeTransferFrom(msg.sender, address(this), miningFeeInOro);
    }

    function finishMining() external {
        uint256 nullifierHash = addressToNullifierHash[msg.sender];
        uint256 startedAt = lastMinedAt[nullifierHash];
        require(startedAt > 0, MiningNotStarted());
        require(block.timestamp >= startedAt + miningInterval, MiningIntervalNotElapsed());

        // Calculate reward
        uint256 randomBonus = (maxBonusReward * (block.timestamp % 7)) / 6;
        uint256 rewardAmount = baseReward + randomBonus;

        // Check for and apply referral bonus
        address remindedUser = lastRemindedAddress[nullifierHash];
        if (remindedUser != address(0)) {
            uint256 remindedNullifierHash = addressToNullifierHash[remindedUser];
            uint256 remindedUserStartTime = lastMinedAt[remindedNullifierHash];
            if (
                remindedUserStartTime > startedAt && remindedUserStartTime - startedAt < miningInterval
                    && remindedUser != msg.sender
            ) {
                rewardAmount = (rewardAmount * (MAX_BPS + referralBonusBps)) / MAX_BPS;
            }
        }

        delete lastMinedAt[nullifierHash];
        delete lastRemindedAddress[nullifierHash];
        delete addressToNullifierHash[msg.sender];

        DIAMANTE.safeTransfer(msg.sender, rewardAmount);
    }

    /*//////////////////////////////////////////////////////////////////////////////
    //                                    ADMIN
    //////////////////////////////////////////////////////////////////////////////*/

    function setMiningFeeInOro(uint256 newFee) external onlyOwner {
        miningFeeInOro = newFee;
    }

    function setMiningInterval(uint256 newInterval) external onlyOwner {
        miningInterval = newInterval;
    }

    function setBaseReward(uint256 newBaseReward) external onlyOwner {
        baseReward = newBaseReward;
    }

    function setMaxBonusReward(uint256 newMaxBonusReward) external onlyOwner {
        maxBonusReward = newMaxBonusReward;
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
