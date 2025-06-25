// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { DiamanteMine } from "src/DiamanteMine.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockWorldID } from "./mocks/MockWorldID.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract DiamanteMineTest is Test {
    DiamanteMine public diamanteMine;
    MockERC20 public oroToken;
    MockERC20 public diamanteToken;
    MockWorldID public mockWorldID;

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public owner = makeAddr("owner");

    uint256 public constant INITIAL_DIAMANTE_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant MINING_FEE = 1 * 1e18;
    uint256 public constant BASE_REWARD = 0.1 * 1e18;
    uint256 public constant MAX_BONUS_REWARD = 0.9 * 1e18;
    uint256 public constant REFERRAL_BONUS_BPS = 1000; // 10%
    uint256 public constant MINING_INTERVAL = 24 hours;

    function setUp() public {
        vm.startPrank(owner);
        // Deploy mock tokens
        oroToken = new MockERC20("ORO Token", "ORO");
        diamanteToken = new MockERC20("Diamante Token", "DIAMANTE");

        // Deploy mock World ID
        mockWorldID = new MockWorldID();

        // Deploy DiamanteMine contract
        diamanteMine = new DiamanteMine(
            diamanteToken,
            oroToken,
            MINING_FEE,
            BASE_REWARD,
            MAX_BONUS_REWARD,
            REFERRAL_BONUS_BPS,
            MINING_INTERVAL,
            mockWorldID,
            "app_test",
            "action_test"
        );

        // Fund the DiamanteMine contract with Diamante tokens
        diamanteToken.mint(address(diamanteMine), INITIAL_DIAMANTE_SUPPLY);
        vm.stopPrank();

        // Fund users with ORO tokens
        oroToken.mint(user1, 1000 * 1e18);
        oroToken.mint(user2, 1000 * 1e18);

        // Users approve ORO spending by the DiamanteMine contract
        vm.prank(user1);
        oroToken.approve(address(diamanteMine), type(uint256).max);
        vm.prank(user2);
        oroToken.approve(address(diamanteMine), type(uint256).max);
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function _getProof(address user) internal pure returns (uint256 root, uint256 nullifier, uint256[8] memory proof) {
        root = 123;
        nullifier = uint256(keccak256(abi.encodePacked(user)));
        proof = [uint256(1), 2, 3, 4, 5, 6, 7, 8];
    }

    function test_StartMining_Success() public {
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        vm.expectEmit(true, true, true, true);
        emit DiamanteMine.StartedMining(user1, user2, nullifier);
        diamanteMine.startMining(root, nullifier, proof, user2);

        assertEq(oroToken.balanceOf(user1), (1000 * 1e18) - MINING_FEE, "User1 ORO balance should decrease");
        assertEq(oroToken.balanceOf(address(diamanteMine)), MINING_FEE, "Contract ORO balance should increase");
        assertTrue(diamanteMine.lastMinedAt(nullifier) > 0, "Mining timestamp should be set");
        assertEq(diamanteMine.lastRemindedAddress(nullifier), user2, "Reminded address should be set to user2");
    }

    function test_FinishMining_Success_NoBonus() public {
        // 1. User1 starts mining
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, address(0));

        // 2. Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // 3. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);

        // We can't check data part of event because reward is non-deterministic
        vm.expectEmit(true, true, true, false);
        emit DiamanteMine.FinishedMining(user1, address(0), nullifier, 0, 0, 0, false);
        diamanteMine.finishMining();
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        // We can't know the exact reward due to timestamp variance, so we check if it's within the expected range.
        uint256 minReward = diamanteMine.minReward();
        uint256 maxReward = diamanteMine.baseReward() + diamanteMine.maxBonusReward();
        assertTrue(
            finalDiamanteBalance - initialDiamanteBalance >= minReward
                && finalDiamanteBalance - initialDiamanteBalance <= maxReward,
            "User1 should receive a reward within the base range"
        );
    }

    function test_FinishMining_Success_WithBonus() public {
        // Temporarily set maxBonusReward to 0 to make the base reward deterministic for this test
        vm.prank(owner);
        diamanteMine.setMaxBonusReward(0);
        vm.stopPrank();

        // 1. User1 starts mining, reminds User2
        vm.prank(user1);
        (uint256 root1, uint256 nullifier1, uint256[8] memory proof1) = _getProof(user1);
        diamanteMine.startMining(root1, nullifier1, proof1, user2);

        uint256 startTime = block.timestamp;
        vm.warp(startTime + 1);

        // 2. User2 starts mining within the window
        vm.prank(user2);
        (uint256 root2, uint256 nullifier2, uint256[8] memory proof2) = _getProof(user2);
        diamanteMine.startMining(root2, nullifier2, proof2, address(0));

        // 3. Time passes for User1's session to end
        vm.warp(startTime + diamanteMine.miningInterval() + 1);

        // 4. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);
        diamanteMine.finishMining();
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        uint256 rewardReceived = finalDiamanteBalance - initialDiamanteBalance;
        uint256 expectedReward = (diamanteMine.baseReward() * (10_000 + REFERRAL_BONUS_BPS)) / 10_000;
        assertEq(rewardReceived, expectedReward, "User1 should receive the exact boosted base reward");
    }

    function test_Fail_StartMining_TooSoon() public {
        // 1. User1 starts mining
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, address(0));

        // 2. Time passes, but not enough
        vm.warp(block.timestamp + 1 hours);

        // 3. User1 tries to start mining again
        vm.prank(user1);
        vm.expectRevert(DiamanteMine.MiningIntervalNotElapsed.selector);
        // We use the same nullifier here which would be caught by world id, but we want to test our own check
        diamanteMine.startMining(root, nullifier, proof, address(0));
    }

    function test_Fail_FinishMining_TooSoon() public {
        // 1. User1 starts mining
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, address(0));

        // 2. Time passes, but not enough
        vm.warp(block.timestamp + 1 hours);

        // 3. User1 tries to finish mining
        vm.prank(user1);
        vm.expectRevert(DiamanteMine.MiningIntervalNotElapsed.selector);
        diamanteMine.finishMining();
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- VIEW FUNCTION TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_GetUserMiningState() public {
        // 1. Initially, user1 is not mining
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMine.MiningState.NotMining));

        // 2. User1 starts mining
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, address(0));

        // 3. Now, user1 is mining
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMine.MiningState.Mining));

        // 4. Time passes, user1 is ready to finish
        vm.warp(block.timestamp + diamanteMine.miningInterval());
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMine.MiningState.ReadyToFinish));

        // 5. User1 finishes mining
        vm.prank(user1);
        diamanteMine.finishMining();

        // 6. Finally, user1 is not mining again
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMine.MiningState.NotMining));
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- CORE LOGIC TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_ActiveMiners_Count() public {
        assertEq(diamanteMine.activeMiners(), 0, "Initial active miners should be 0");

        // User1 starts mining
        vm.prank(user1);
        (uint256 root1, uint256 nullifier1, uint256[8] memory proof1) = _getProof(user1);
        diamanteMine.startMining(root1, nullifier1, proof1, address(0));
        assertEq(diamanteMine.activeMiners(), 1, "Active miners should be 1 after user1 starts");

        // User2 starts mining
        vm.prank(user2);
        (uint256 root2, uint256 nullifier2, uint256[8] memory proof2) = _getProof(user2);
        diamanteMine.startMining(root2, nullifier2, proof2, address(0));
        assertEq(diamanteMine.activeMiners(), 2, "Active miners should be 2 after user2 starts");

        // User1 finishes mining
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);
        vm.prank(user1);
        diamanteMine.finishMining();
        assertEq(diamanteMine.activeMiners(), 1, "Active miners should be 1 after user1 finishes");

        // User2 finishes mining
        vm.prank(user2);
        diamanteMine.finishMining();
        assertEq(diamanteMine.activeMiners(), 0, "Active miners should be 0 after user2 finishes");
    }

    function test_FinishMining_Fail_Referral_Self() public {
        vm.prank(owner);
        diamanteMine.setMaxBonusReward(0);
        vm.stopPrank();

        // User1 starts mining, reminds themselves
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, user1);

        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        uint256 initialBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);
        (, uint256 referralBonus, bool hasBonus) = diamanteMine.finishMining();
        uint256 finalBalance = diamanteToken.balanceOf(user1);

        assertEq(referralBonus, 0, "Referral bonus should be 0 for self-referral");
        assertFalse(hasBonus, "hasBonus should be false for self-referral");
        assertEq(finalBalance - initialBalance, diamanteMine.baseReward(), "Reward should be base reward only");
    }

    function test_FinishMining_Fail_Referral_TooLate() public {
        vm.prank(owner);
        diamanteMine.setMaxBonusReward(0);
        vm.stopPrank();

        // 1. User1 starts mining, reminds User2
        vm.prank(user1);
        (uint256 root1, uint256 nullifier1, uint256[8] memory proof1) = _getProof(user1);
        diamanteMine.startMining(root1, nullifier1, proof1, user2);
        uint256 user1StartTime = block.timestamp;

        // 2. User2 starts mining, but *after* User1's referral window has closed
        vm.warp(user1StartTime + diamanteMine.miningInterval() + 1);
        vm.prank(user2);
        (uint256 root2, uint256 nullifier2, uint256[8] memory proof2) = _getProof(user2);
        diamanteMine.startMining(root2, nullifier2, proof2, address(0));

        // 3. User1 finishes mining
        uint256 initialBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);
        (, uint256 referralBonus, bool hasBonus) = diamanteMine.finishMining();
        uint256 finalBalance = diamanteToken.balanceOf(user1);

        assertEq(referralBonus, 0, "Referral bonus should be 0 for late referral");
        assertFalse(hasBonus, "hasBonus should be false for late referral");
        assertEq(finalBalance - initialBalance, diamanteMine.baseReward(), "Reward should be base reward only");
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- ADMIN TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_SetMiningFeeInOro() public {
        uint256 newFee = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMiningFeeInOro(newFee);
        assertEq(diamanteMine.miningFeeInOro(), newFee);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMiningFeeInOro(newFee);
    }

    function test_SetMiningInterval() public {
        uint256 newInterval = 48 hours;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMiningInterval(newInterval);
        assertEq(diamanteMine.miningInterval(), newInterval);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMiningInterval(newInterval);
    }

    function test_SetBaseReward() public {
        uint256 newReward = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setBaseReward(newReward);
        assertEq(diamanteMine.baseReward(), newReward);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setBaseReward(newReward);
    }

    function test_SetMaxBonusReward() public {
        uint256 newMaxBonus = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMaxBonusReward(newMaxBonus);
        assertEq(diamanteMine.maxBonusReward(), newMaxBonus);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMaxBonusReward(newMaxBonus);
    }

    function test_SetReferralBonusBps() public {
        uint256 newBps = 2000;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setReferralBonusBps(newBps);
        assertEq(diamanteMine.referralBonusBps(), newBps);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setReferralBonusBps(newBps);
    }

    function test_WithdrawERC20() public {
        // --- Success ---
        vm.startPrank(owner);
        oroToken.mint(address(diamanteMine), 1e18);
        uint256 initialOwnerOro = oroToken.balanceOf(owner);
        uint256 initialContractOro = oroToken.balanceOf(address(diamanteMine));
        diamanteMine.withdrawERC20(IERC20(address(oroToken)), 1e18);
        assertEq(oroToken.balanceOf(owner), initialOwnerOro + 1e18);
        assertEq(oroToken.balanceOf(address(diamanteMine)), initialContractOro - 1e18);
        vm.stopPrank();

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.withdrawERC20(IERC20(address(oroToken)), 1);
    }

    function test_DepositERC20() public {
        // --- Success ---
        vm.startPrank(owner);
        oroToken.mint(owner, 1e18);
        oroToken.approve(address(diamanteMine), 1e18);
        uint256 initialContractOro = oroToken.balanceOf(address(diamanteMine));
        diamanteMine.depositERC20(IERC20(address(oroToken)), 1e18);
        assertEq(oroToken.balanceOf(address(diamanteMine)), initialContractOro + 1e18);
        vm.stopPrank();

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.depositERC20(IERC20(address(oroToken)), 1);
    }
}
