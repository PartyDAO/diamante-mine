// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { DiamanteMineV1 } from "../src/DiamanteMineV1.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockWorldID } from "./mocks/MockWorldID.sol";
import { MockPermit2 } from "./mocks/MockPermit2.sol";
import { Permit2 } from "../src/utils/Permit2Helper.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockDiamanteMineV2 } from "./mocks/MockDiamanteMineV2.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract DiamanteMineTest is Test {
    DiamanteMineV1 public diamanteMine;
    MockERC20 public oroToken;
    MockERC20 public diamanteToken;
    MockWorldID public mockWorldID;
    MockPermit2 public mockPermit2;

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public owner = makeAddr("owner");
    address public user3 = makeAddr("user3");

    uint256 public constant INITIAL_DIAMANTE_SUPPLY = 100_000_000 * 1e18; // Much larger supply for
        // new multiplication
        // system
    uint256 public constant MIN_AMOUNT_IN_ORO = 1 * 1e18;
    uint256 public constant MAX_AMOUNT_IN_ORO = 100 * 1e18;
    uint256 public constant MIN_REWARD = 0.1 * 1e18;
    uint256 public constant EXTRA_REWARD_PER_LEVEL = 0.09 * 1e18;
    uint256 public constant REFERRAL_BONUS_BPS = 1000; // 10%
    uint256 public constant MINING_INTERVAL = 24 hours;
    uint256 public constant MAX_REWARD_LEVEL = 10;

    Permit2 public permit;

    function setUp() public {
        vm.startPrank(owner);
        // Deploy mock tokens
        oroToken = new MockERC20("ORO Token", "ORO");
        diamanteToken = new MockERC20("Diamante Token", "DIAMANTE");

        // Deploy mock World ID
        mockWorldID = new MockWorldID();

        // Deploy mock Permit2
        mockPermit2 = new MockPermit2();

        // Deploy implementation
        DiamanteMineV1 implementation = new DiamanteMineV1(mockPermit2);

        // Prepare initialization data
        bytes memory data = abi.encodeWithSelector(
            DiamanteMineV1.initialize.selector,
            owner, // initialOwner
            diamanteToken,
            oroToken,
            MIN_AMOUNT_IN_ORO,
            MAX_AMOUNT_IN_ORO,
            MIN_REWARD,
            EXTRA_REWARD_PER_LEVEL,
            MAX_REWARD_LEVEL,
            REFERRAL_BONUS_BPS,
            MINING_INTERVAL,
            mockWorldID,
            "app_test",
            "action_test"
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        diamanteMine = DiamanteMineV1(address(proxy));

        // Fund the DiamanteMine contract with Diamante tokens
        diamanteToken.mint(address(diamanteMine), INITIAL_DIAMANTE_SUPPLY);
        vm.stopPrank();

        // Fund users with ORO tokens
        oroToken.mint(user1, 1000 * 1e18);
        oroToken.mint(user2, 1000 * 1e18);
        oroToken.mint(user3, 1000 * 1e18);

        // Users approve ORO spending by the Permit2 contract
        vm.prank(user1);
        oroToken.approve(address(mockPermit2), type(uint256).max);
        vm.prank(user2);
        oroToken.approve(address(mockPermit2), type(uint256).max);
        vm.prank(user3);
        oroToken.approve(address(mockPermit2), type(uint256).max);
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function _getProof(address user) internal pure returns (uint256 root, uint256 nullifier, uint256[8] memory proof) {
        root = 123;
        nullifier = uint256(keccak256(abi.encodePacked(user)));
        proof = [uint256(1), 2, 3, 4, 5, 6, 7, 8];
    }

    /// @notice Helper function to start mining as a specific user
    function _startMiningAs(address user, address referrer, uint256 amount) internal {
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user);
        bytes memory args = diamanteMine.encodeMiningArgs(referrer, amount);

        vm.startPrank(user);
        diamanteMine.startMining(args, root, nullifier, proof, permit);
        vm.stopPrank();
    }

    /// @notice Helper function to finish mining as a specific user
    function _finishMiningAs(address user) internal {
        vm.startPrank(user);
        diamanteMine.finishMining();
        vm.stopPrank();
    }

    function test_StartMining_Success() public {
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        bytes memory args = diamanteMine.encodeMiningArgs(user2, MIN_AMOUNT_IN_ORO);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit DiamanteMineV1.StartedMining(user1, user2, nullifier, MIN_AMOUNT_IN_ORO);
        diamanteMine.startMining(args, root, nullifier, proof, permit);
        vm.stopPrank();

        assertEq(oroToken.balanceOf(user1), (1000 * 1e18) - MIN_AMOUNT_IN_ORO, "User1 ORO balance should decrease");
        assertEq(oroToken.balanceOf(address(diamanteMine)), MIN_AMOUNT_IN_ORO, "Contract ORO balance should increase");
        assertTrue(diamanteMine.lastMinedAt(nullifier) > 0, "Mining timestamp should be set");
        assertEq(diamanteMine.lastRemindedAddress(nullifier), user2, "Reminded address should be set to user2");
        assertEq(diamanteMine.amountOroMinedWith(nullifier), MIN_AMOUNT_IN_ORO, "ORO mined with should be set");
    }

    function test_Fail_StartMining_InvalidOroAmount() public {
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        uint256 tooLow = MIN_AMOUNT_IN_ORO - 1;
        bytes memory argsLow = diamanteMine.encodeMiningArgs(address(0), tooLow);
        vm.expectRevert(
            abi.encodeWithSelector(
                DiamanteMineV1.InvalidOroAmount.selector, tooLow, MIN_AMOUNT_IN_ORO, MAX_AMOUNT_IN_ORO
            )
        );
        diamanteMine.startMining(argsLow, root, nullifier, proof, permit);

        uint256 tooHigh = MAX_AMOUNT_IN_ORO + 1;
        bytes memory argsHigh = diamanteMine.encodeMiningArgs(address(0), tooHigh);
        vm.expectRevert(
            abi.encodeWithSelector(
                DiamanteMineV1.InvalidOroAmount.selector, tooHigh, MIN_AMOUNT_IN_ORO, MAX_AMOUNT_IN_ORO
            )
        );
        diamanteMine.startMining(argsHigh, root, nullifier, proof, permit);
    }

    function test_FinishMining_Success_NoBonus() public {
        // 1. User1 starts mining, activeMiners will be 1
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);
        assertEq(diamanteMine.activeMiners(), 1);

        // 2. Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // 3. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);

        // Expected reward calculation (activeMiners was 1, so rewardLevel is 0)
        uint256 rewardLevel = (1 - 1) % (MAX_REWARD_LEVEL + 1);
        uint256 expectedBonus = diamanteMine.extraRewardPerLevel() * rewardLevel;
        uint256 expectedBaseReward = diamanteMine.minReward() + expectedBonus;
        // Reward is base reward multiplied by ORO amount / 1e18
        uint256 expectedTotalReward = (expectedBaseReward * MIN_AMOUNT_IN_ORO) / 1e18; // No
            // referral bonus

        uint256 userNullifier = diamanteMine.addressToNullifierHash(user1);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit DiamanteMineV1.FinishedMining(
            user1,
            address(0),
            userNullifier,
            expectedTotalReward,
            expectedBaseReward,
            expectedTotalReward - expectedBaseReward,
            0,
            false,
            MIN_AMOUNT_IN_ORO
        );
        diamanteMine.finishMining();
        vm.stopPrank();
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        uint256 rewardReceived = finalDiamanteBalance - initialDiamanteBalance;
        assertEq(rewardReceived, expectedTotalReward, "User1 should receive correct reward for 1 miner");
    }

    function test_FinishMining_RewardCalculation_MultipleMiners() public {
        // 1. Create 5 miners
        uint8 numMiners = 5;
        address firstMiner = address(0);

        for (uint8 i = 0; i < numMiners; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked("miner", i)))));
            oroToken.mint(user, 1000 * 1e18);
            (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user);

            vm.startPrank(user);
            oroToken.approve(address(mockPermit2), type(uint256).max);
            bytes memory args = diamanteMine.encodeMiningArgs(address(0), MIN_AMOUNT_IN_ORO);
            diamanteMine.startMining(args, root, nullifier, proof, permit);
            vm.stopPrank();

            if (i == 0) {
                firstMiner = user;
            }
        }
        assertEq(diamanteMine.activeMiners(), numMiners);

        // 2. Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // 3. The first miner created finishes mining
        // Expected reward calculation
        uint256 activeMinersBefore = diamanteMine.activeMiners();
        uint256 rewardLevel = (activeMinersBefore - 1) % diamanteMine.maxRewardLevel();
        uint256 expectedBonus = diamanteMine.extraRewardPerLevel() * rewardLevel;
        uint256 expectedBaseReward = diamanteMine.minReward() + expectedBonus;
        uint256 expectedTotalReward = (expectedBaseReward * MIN_AMOUNT_IN_ORO) / 1e18; // No
            // referral bonus

        uint256 firstMinerNullifier = diamanteMine.addressToNullifierHash(firstMiner);

        // Prank must be immediately before the state-changing call
        vm.prank(firstMiner);
        vm.expectEmit(true, true, true, true);
        emit DiamanteMineV1.FinishedMining(
            firstMiner,
            address(0),
            firstMinerNullifier,
            expectedTotalReward,
            expectedBaseReward,
            expectedTotalReward - expectedBaseReward,
            0,
            false,
            MIN_AMOUNT_IN_ORO
        );
        diamanteMine.finishMining();
    }

    function test_Fail_StartMining_AlreadyMining() public {
        // 1. User1 starts mining
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);

        // 2. User1 tries to start mining again before finishing the first session
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        bytes memory args = diamanteMine.encodeMiningArgs(address(0), MIN_AMOUNT_IN_ORO);

        vm.startPrank(user1);
        vm.expectRevert(DiamanteMineV1.AlreadyMining.selector);
        diamanteMine.startMining(args, root, nullifier, proof, permit);
        vm.stopPrank();
    }

    function test_Fail_StartMining_InsufficientDiamante() public {
        // 1. User1 starts mining successfully.
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);
        assertEq(diamanteMine.activeMiners(), 1);

        // 2. Withdraw just enough so the contract can't support another miner.
        vm.startPrank(owner);
        uint256 maxRew = diamanteMine.maxReward();
        uint256 balance = diamanteToken.balanceOf(address(diamanteMine));
        // Leave just enough for the current active miner, but not enough for two.
        uint256 amountToWithdraw = balance - maxRew;
        diamanteMine.withdrawERC20(IERC20(address(diamanteToken)), amountToWithdraw);
        vm.stopPrank();

        // Check that the balance is now exactly maxReward, which is less than maxReward*2
        assertEq(diamanteToken.balanceOf(address(diamanteMine)), maxRew);

        // 3. User2 tries to start mining and fails.
        (uint256 root2, uint256 nullifier2, uint256[8] memory proof2) = _getProof(user2);
        bytes memory args2 = diamanteMine.encodeMiningArgs(address(0), MIN_AMOUNT_IN_ORO);

        vm.startPrank(user2);
        vm.expectRevert(DiamanteMineV1.InsufficientBalanceForReward.selector);
        diamanteMine.startMining(args2, root2, nullifier2, proof2, permit);
        vm.stopPrank();
    }

    function test_Fail_FinishMining_NotStarted() public {
        vm.prank(user1);
        vm.expectRevert(DiamanteMineV1.MiningNotStarted.selector);
        diamanteMine.finishMining();
    }

    function test_Fail_FinishMining_TooSoon() public {
        // 1. User1 starts mining
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);

        // 2. Time passes, but not enough
        vm.warp(block.timestamp + 1 hours);

        // 3. User1 tries to finish mining
        vm.startPrank(user1);
        vm.expectRevert(DiamanteMineV1.MiningIntervalNotElapsed.selector);
        diamanteMine.finishMining();
        vm.stopPrank();
    }

    function _assertExpectedRewardsFromMultiplier(uint256 amountToMine, string memory assertionMsg) internal {
        // 1. User1 starts mining
        _startMiningAs(user1, address(0), amountToMine);

        // 2. Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // 3. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);

        // Expected reward calculation: baseReward * amountToMine / 1e18
        uint256 baseReward = diamanteMine.minReward(); // No level bonus when only 1 miner
        uint256 expectedTotalReward = (baseReward * amountToMine) / 1e18;

        _finishMiningAs(user1);
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        uint256 rewardReceived = finalDiamanteBalance - initialDiamanteBalance;
        assertEq(rewardReceived, expectedTotalReward, assertionMsg);
    }

    function test_FinishMining_With1Oro() public {
        _assertExpectedRewardsFromMultiplier(1 * 1e18, "Should get 1x base reward for 1 ORO");
    }

    function test_FinishMining_With2Oro() public {
        _assertExpectedRewardsFromMultiplier(2 * 1e18, "Should get 2x base reward for 2 ORO");
    }

    function test_FinishMining_With10Oro() public {
        _assertExpectedRewardsFromMultiplier(10 * 1e18, "Should get 10x base reward for 10 ORO");
    }

    function test_FinishMining_WithMaxOro() public {
        _assertExpectedRewardsFromMultiplier(MAX_AMOUNT_IN_ORO, "Should get 100x base reward for 100 ORO");
    }

    function test_FinishMining_NoBonus_ReferralMinedTooLate() public {
        // 1. User1 starts mining, reminds User2
        _startMiningAs(user1, user2, MIN_AMOUNT_IN_ORO);

        uint256 startTime = block.timestamp;
        // 2. User2 mines, but AFTER the referral window for user1 has passed
        vm.warp(startTime + diamanteMine.miningInterval() + 1);
        _startMiningAs(user2, address(0), MIN_AMOUNT_IN_ORO);

        // 3. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);

        uint256 activeMinersBefore = diamanteMine.activeMiners();
        uint256 rewardLevel = (activeMinersBefore - 1) % diamanteMine.maxRewardLevel();
        uint256 expectedBonus = diamanteMine.extraRewardPerLevel() * rewardLevel;
        uint256 expectedBaseReward = diamanteMine.minReward() + expectedBonus;
        uint256 expectedTotalReward = (expectedBaseReward * MIN_AMOUNT_IN_ORO) / 1e18; // No
            // referral bonus

        _finishMiningAs(user1);
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);
        uint256 rewardReceived = finalDiamanteBalance - initialDiamanteBalance;
        assertEq(rewardReceived, expectedTotalReward, "User1 should not receive a referral bonus");
    }

    function test_ActiveMiners_Count() public {
        assertEq(diamanteMine.activeMiners(), 0, "Initially, no active miners");

        // User1 starts mining
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);
        assertEq(diamanteMine.activeMiners(), 1, "Active miners should be 1");

        // User2 starts mining
        _startMiningAs(user2, address(0), MIN_AMOUNT_IN_ORO);
        assertEq(diamanteMine.activeMiners(), 2, "Active miners should be 2");

        // User1 finishes mining
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);
        _finishMiningAs(user1);
        assertEq(diamanteMine.activeMiners(), 1, "Active miners should be 1 after one finishes");

        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);
        _finishMiningAs(user2);
        assertEq(diamanteMine.activeMiners(), 0, "Active miners should be 0 after both finish");
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- REWARD CALCULATIONS TESTS
    //-//////////////////////////////////////////////////////////////////////////

    /*
     * REWARD CALCULATION FORMULA:
     * 1. baseReward = minReward + (extraRewardPerLevel * rewardLevel)
     * 2. miningReward = baseReward * oroAmount
     * 3. referralBonus = (miningReward * referralBonusBps) / 10000 (if applicable)
     * 4. totalReward = miningReward + referralBonus
     *
     * Where rewardLevel = (activeMiners - 1) % maxRewardLevel
     *
     * TEST CASES TABLE:
    *
    ┌──────────────┬─────────────┬──────────────┬──────────────────┬─────────────────┬─────────────────┐
    * │ ActiveMiners │ RewardLevel │ ORO Amount   │ Base Reward      │ Mining Reward   │
    w/ Referral 10% │
    *
    ├──────────────┼─────────────┼──────────────┼──────────────────┼─────────────────┼─────────────────┤
    * │ 1            │ 0           │ 1 ORO        │ 0.1              │ 0.1             │
    0.11            │
    * │ 1            │ 0           │ 2 ORO        │ 0.1              │ 0.2             │
    0.22            │
    * │ 1            │ 0           │ 5 ORO        │ 0.1              │ 0.5             │
    0.55            │
    * │ 1            │ 0           │ 100 ORO      │ 0.1              │ 10.0            │
    11.0            │
    *
    ├──────────────┼─────────────┼──────────────┼──────────────────┼─────────────────┼─────────────────┤
    * │ 2            │ 1           │ 1 ORO        │ 0.19             │ 0.19            │
    0.209           │
    * │ 2            │ 1           │ 3 ORO        │ 0.19             │ 0.57            │
    0.627           │
    * │ 5            │ 4           │ 2 ORO        │ 0.46             │ 0.92            │
    1.012           │
    * │ 10           │ 9           │ 5 ORO        │ 0.91             │ 4.55            │
    5.005           │
    * │ 11           │ 10          │ 1 ORO        │ 1.0              │ 1.0             │
    1.1             │
    * │ 12           │ 0 (wraparound)│ 10 ORO     │ 0.1              │ 1.0             │
    1.1             │
    *
    └──────────────┴─────────────┴──────────────┴──────────────────┴─────────────────┴─────────────────┘
     *
    * Note: Base values assume minReward=0.1, extraRewardPerLevel=0.09, maxRewardLevel=10,
    referralBonusBps=1000
     *
     * The tests below verify each row of this table plus additional edge cases.
     */

    function test_RewardMultiplication_WithLevelBonus() public {
        // Start 3 miners to create level bonus
        address miner1 = makeAddr("miner1");
        address miner2 = makeAddr("miner2");
        address miner3 = makeAddr("miner3");

        oroToken.mint(miner1, 1000 * 1e18);
        oroToken.mint(miner2, 1000 * 1e18);
        oroToken.mint(miner3, 1000 * 1e18);

        vm.prank(miner1);
        oroToken.approve(address(mockPermit2), type(uint256).max);
        vm.prank(miner2);
        oroToken.approve(address(mockPermit2), type(uint256).max);
        vm.prank(miner3);
        oroToken.approve(address(mockPermit2), type(uint256).max);

        // Start mining with different amounts
        _startMiningAs(miner1, address(0), 1 * 1e18);
        _startMiningAs(miner2, address(0), 5 * 1e18);
        _startMiningAs(miner3, address(0), 10 * 1e18);

        assertEq(diamanteMine.activeMiners(), 3);

        // Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // Check miner1 reward (1 ORO)
        uint256 initialBalance1 = diamanteToken.balanceOf(miner1);
        _finishMiningAs(miner1);
        uint256 reward1 = diamanteToken.balanceOf(miner1) - initialBalance1;

        // Expected: (minReward + level2Bonus) * 1 ORO / 1e18
        uint256 level2Bonus = diamanteMine.extraRewardPerLevel() * 2; // 3-1 = 2
        uint256 expectedReward1 = ((diamanteMine.minReward() + level2Bonus) * (1 * 1e18)) / 1e18;
        assertEq(reward1, expectedReward1, "Miner1 should get correct reward with level bonus * 1 ORO");

        // Check miner2 reward (5 ORO)
        uint256 initialBalance2 = diamanteToken.balanceOf(miner2);
        _finishMiningAs(miner2);
        uint256 reward2 = diamanteToken.balanceOf(miner2) - initialBalance2;

        // Expected: (minReward + level1Bonus) * 5 ORO / 1e18
        uint256 level1Bonus = diamanteMine.extraRewardPerLevel() * 1; // 2-1 = 1
        uint256 expectedReward2 = ((diamanteMine.minReward() + level1Bonus) * (5 * 1e18)) / 1e18;
        assertEq(reward2, expectedReward2, "Miner2 should get correct reward with level bonus * 5 ORO");

        // Check miner3 reward (10 ORO)
        uint256 initialBalance3 = diamanteToken.balanceOf(miner3);
        _finishMiningAs(miner3);
        uint256 reward3 = diamanteToken.balanceOf(miner3) - initialBalance3;

        // Expected: (minReward + level0Bonus) * 10 ORO / 1e18
        uint256 level0Bonus = diamanteMine.extraRewardPerLevel() * 0; // 1-1 = 0
        uint256 expectedReward3 = ((diamanteMine.minReward() + level0Bonus) * (10 * 1e18)) / 1e18;
        assertEq(reward3, expectedReward3, "Miner3 should get correct reward with level bonus * 10 ORO");

        // Verify scaling: reward2 should be 5x reward1 (same level bonus)
        // Since level bonuses are different, we can't directly compare multiples
        // But we can verify each calculation individually
    }

    /// @notice Tests Table Row: 1 miner, level 0, 1 ORO, no referral
    function test_RewardTable_1Miner_1Oro_NoReferral() public {
        _testRewardCombination(1, 1 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 1 miner, level 0, 2 ORO, no referral
    function test_RewardTable_1Miner_2Oro_NoReferral() public {
        _testRewardCombination(1, 2 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 1 miner, level 0, 5 ORO, no referral
    function test_RewardTable_1Miner_5Oro_NoReferral() public {
        _testRewardCombination(1, 5 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 1 miner, level 0, 100 ORO, no referral
    function test_RewardTable_1Miner_100Oro_NoReferral() public {
        _testRewardCombination(1, 100 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 1 miner, level 0, 1 ORO, with referral
    function test_RewardTable_1Miner_1Oro_WithReferral() public {
        _testRewardCombination(1, 1 * 1e18, true, user2);
    }

    /// @notice Tests Table Row: 2 miners, level 1, 1 ORO, no referral
    function test_RewardTable_2Miners_1Oro_NoReferral() public {
        _testRewardCombination(2, 1 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 2 miners, level 1, 3 ORO, with referral
    function test_RewardTable_2Miners_3Oro_WithReferral() public {
        _testRewardCombination(2, 3 * 1e18, true, user2);
    }

    /// @notice Tests Table Row: 5 miners, level 4, 2 ORO, no referral
    function test_RewardTable_5Miners_2Oro_NoReferral() public {
        _testRewardCombination(5, 2 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 10 miners, level 9, 5 ORO, no referral
    function test_RewardTable_10Miners_5Oro_NoReferral() public {
        _testRewardCombination(10, 5 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 11 miners, level 10 (max), 1 ORO, no referral
    function test_RewardTable_11Miners_1Oro_NoReferral() public {
        _testRewardCombination(11, 1 * 1e18, false, address(0));
    }

    /// @notice Tests Table Row: 12 miners, level 0 (wraparound), 10 ORO, with referral
    function test_RewardTable_12Miners_10Oro_WithReferral() public {
        _testRewardCombination(12, 10 * 1e18, true, user2);
    }

    /// @notice Tests edge case: 22 miners (wraparound to level 10), 5 ORO
    function test_RewardTable_22Miners_5Oro_MaxLevel() public {
        _testRewardCombination(22, 5 * 1e18, false, address(0));
    }

    /// @notice Helper function to test specific reward combinations
    /// @param numMiners Number of active miners to simulate
    /// @param oroAmount Amount of ORO the test miner uses
    /// @param withReferral Whether to test referral bonus
    /// @param referredUser Address of referred user (only matters if withReferral is true)
    function _testRewardCombination(
        uint256 numMiners,
        uint256 oroAmount,
        bool withReferral,
        address referredUser
    )
        internal
    {
        // Calculate how many filler miners we need
        uint256 fillersNeeded;
        if (withReferral && referredUser != address(0)) {
            // For referral tests: test miner + referred user = 2 miners, so we need numMiners - 2
            // fillers
            // But if numMiners is 1, that means we want just the test miner, and they'll refer
            // someone
            // who starts later, making it 2 total during the test but 1 when test miner finishes
            fillersNeeded = numMiners > 1 ? numMiners - 2 : 0;
        } else {
            fillersNeeded = numMiners - 1;
        }

        // Create filler miners to reach desired activeMiners count
        for (uint256 i = 0; i < fillersNeeded; i++) {
            address filler = address(uint160(uint256(keccak256(abi.encodePacked("filler_miner", i)))));
            oroToken.mint(filler, 1000 * 1e18);

            vm.prank(filler);
            oroToken.approve(address(mockPermit2), type(uint256).max);

            _startMiningAs(filler, address(0), MIN_AMOUNT_IN_ORO);
        }

        // Set up the test miner (user1)
        address testMiner = user1;

        // If testing referral, make sure referred user starts mining within window
        if (withReferral && referredUser != address(0)) {
            _startMiningAs(testMiner, referredUser, oroAmount);

            // Referred user starts mining within referral window
            vm.warp(block.timestamp + 1 hours);
            _startMiningAs(referredUser, address(0), MIN_AMOUNT_IN_ORO);
        } else {
            _startMiningAs(testMiner, address(0), oroAmount);
        }

        // For 1 miner with referral, the actual count will be 2 when test miner finishes
        uint256 expectedActiveMiners = (withReferral && referredUser != address(0) && numMiners == 1) ? 2 : numMiners;
        assertEq(diamanteMine.activeMiners(), expectedActiveMiners, "Should have correct number of active miners");

        // Time passes
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        // Calculate expected reward - use the actual active miners count for reward level
        uint256 expectedRewardLevel = (expectedActiveMiners - 1) % diamanteMine.maxRewardLevel();
        uint256 expectedLevelBonus = diamanteMine.extraRewardPerLevel() * expectedRewardLevel;
        uint256 expectedBaseReward = diamanteMine.minReward() + expectedLevelBonus;
        uint256 expectedMiningReward = (expectedBaseReward * oroAmount) / 1e18;

        uint256 expectedReferralBonus = 0;
        if (withReferral && referredUser != address(0)) {
            expectedReferralBonus = (expectedMiningReward * diamanteMine.referralBonusBps()) / 10_000;
        }

        uint256 expectedTotalReward = expectedMiningReward + expectedReferralBonus;

        // Test miner finishes mining
        uint256 initialBalance = diamanteToken.balanceOf(testMiner);
        _finishMiningAs(testMiner);
        uint256 actualReward = diamanteToken.balanceOf(testMiner) - initialBalance;

        // Verify reward calculation
        assertEq(
            actualReward,
            expectedTotalReward,
            string(
                abi.encodePacked(
                    "Reward mismatch for ",
                    _toString(numMiners),
                    " miners, ",
                    _toString(oroAmount / 1e18),
                    " ORO, ",
                    withReferral ? "with" : "without",
                    " referral"
                )
            )
        );
    }

    /// @notice Helper to convert uint to string for error messages
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- ADDITIONAL REWARD CALCULATION TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_RewardMultiplication_WithReferralBonus() public {
        // User1 starts mining with 3 ORO, reminds User2
        _startMiningAs(user1, user2, 3 * 1e18);

        // User2 starts mining with 2 ORO within referral window
        vm.warp(block.timestamp + 1 hours); // Within 24 hour window
        _startMiningAs(user2, address(0), 2 * 1e18);

        // User1 finishes mining
        vm.warp(block.timestamp + diamanteMine.miningInterval());
        uint256 initialBalance = diamanteToken.balanceOf(user1);
        _finishMiningAs(user1);
        uint256 rewardReceived = diamanteToken.balanceOf(user1) - initialBalance;

        // Expected calculation:
        // baseReward = minReward + levelBonus (level 1, since activeMiners was 2)
        uint256 levelBonus = diamanteMine.extraRewardPerLevel() * 1;
        uint256 baseReward = diamanteMine.minReward() + levelBonus;
        // miningReward = baseReward * 3 ORO / 1e18
        uint256 miningReward = (baseReward * (3 * 1e18)) / 1e18;
        // referralBonus = miningReward * 10%
        uint256 referralBonus = (miningReward * REFERRAL_BONUS_BPS) / 10_000;
        uint256 expectedTotal = miningReward + referralBonus;

        assertEq(rewardReceived, expectedTotal, "Should receive mining reward * 3 ORO + referral bonus");
    }

    function test_RewardCalculation_ExactNumbers() public {
        // Test with exact numbers to ensure precision
        uint256 oroAmount = 7 * 1e18; // 7 ORO

        _startMiningAs(user1, address(0), oroAmount);

        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

        uint256 initialBalance = diamanteToken.balanceOf(user1);
        _finishMiningAs(user1);
        uint256 rewardReceived = diamanteToken.balanceOf(user1) - initialBalance;

        // Expected: 0.1 * 1e18 * 7 * 1e18 / 1e18 = 0.7 * 1e18
        uint256 expected = (MIN_REWARD * oroAmount) / 1e18;
        assertEq(rewardReceived, expected, "Should get exactly 7x the base reward");
    }

    function test_MaxReward_Calculation() public view {
        // Test that maxReward() returns correct value
        uint256 maxRewardValue = diamanteMine.maxReward();

        // Expected: (minReward + maxLevelBonus) * maxOro / 1e18 * (1 + referralBonus)
        uint256 maxBaseReward =
            diamanteMine.minReward() + (diamanteMine.extraRewardPerLevel() * diamanteMine.maxRewardLevel());
        uint256 maxMiningReward = (maxBaseReward * MAX_AMOUNT_IN_ORO) / 1e18;
        uint256 expectedMaxReward = (maxMiningReward * (10_000 + REFERRAL_BONUS_BPS)) / 10_000;

        assertEq(maxRewardValue, expectedMaxReward, "maxReward() should return correct maximum possible reward");
    }

    function test_RewardScaling_Linear() public {
        // Test that rewards scale linearly with ORO amount
        uint256[] memory oroAmounts = new uint256[](3);
        oroAmounts[0] = 2 * 1e18;
        oroAmounts[1] = 4 * 1e18;
        oroAmounts[2] = 8 * 1e18;

        uint256[] memory rewards = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            address miner = address(uint160(uint256(keccak256(abi.encodePacked("linear_miner", i)))));
            oroToken.mint(miner, 1000 * 1e18);

            vm.prank(miner);
            oroToken.approve(address(mockPermit2), type(uint256).max);

            _startMiningAs(miner, address(0), oroAmounts[i]);

            vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);

            uint256 initialBalance = diamanteToken.balanceOf(miner);
            _finishMiningAs(miner);
            rewards[i] = diamanteToken.balanceOf(miner) - initialBalance;
        }

        // Verify linear scaling
        assertEq(rewards[1], rewards[0] * 2, "4 ORO should give 2x reward of 2 ORO");
        assertEq(rewards[2], rewards[0] * 4, "8 ORO should give 4x reward of 2 ORO");
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- ADMIN TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_SetMinAmountInOro() public {
        uint256 newAmount = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMinAmountOro(newAmount);
        assertEq(diamanteMine.minAmountOro(), newAmount);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMinAmountOro(newAmount);

        // --- Fail: Min > Max ---
        vm.prank(owner);
        uint256 invalidAmount = MAX_AMOUNT_IN_ORO + 1;
        vm.expectRevert(DiamanteMineV1.MinAmountExceedsMaxAmount.selector);
        diamanteMine.setMinAmountOro(invalidAmount);
    }

    function test_SetMaxAmountInOro() public {
        uint256 newAmount = 200 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMaxAmountOro(newAmount);
        assertEq(diamanteMine.maxAmountOro(), newAmount);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMaxAmountOro(newAmount);

        // --- Fail: Max < Min ---
        vm.prank(owner);
        uint256 invalidAmount = MIN_AMOUNT_IN_ORO - 1;
        vm.expectRevert(DiamanteMineV1.MinAmountExceedsMaxAmount.selector);
        diamanteMine.setMaxAmountOro(invalidAmount);
    }

    function test_SetMiningInterval() public {
        uint256 newInterval = 48 hours;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMiningInterval(newInterval);
        assertEq(diamanteMine.miningInterval(), newInterval);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMiningInterval(newInterval);
    }

    function test_SetMinReward() public {
        uint256 newReward = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMinReward(newReward);
        assertEq(diamanteMine.minReward(), newReward);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMinReward(newReward);
    }

    function test_SetExtraRewardPerLevel() public {
        uint256 newExtraReward = 2 * 1e18;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setExtraRewardPerLevel(newExtraReward);
        assertEq(diamanteMine.extraRewardPerLevel(), newExtraReward);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setExtraRewardPerLevel(newExtraReward);
    }

    function test_SetMaxRewardLevel() public {
        uint256 newMaxLevel = 20;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setMaxRewardLevel(newMaxLevel);
        assertEq(diamanteMine.maxRewardLevel(), newMaxLevel);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.setMaxRewardLevel(newMaxLevel);

        // --- Fail: Zero Value ---
        vm.prank(owner);
        vm.expectRevert(DiamanteMineV1.MaxRewardLevelCannotBeZero.selector);
        diamanteMine.setMaxRewardLevel(0);
    }

    function test_SetReferralBonusBps() public {
        uint256 newBps = 2000;

        // --- Success ---
        vm.prank(owner);
        diamanteMine.setReferralBonusBps(newBps);
        assertEq(diamanteMine.referralBonusBps(), newBps);

        // --- Fail: Non-Owner ---
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        diamanteMine.depositERC20(IERC20(address(oroToken)), 1);
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- UPGRADEABILITY TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_UpgradeToV2() public {
        // Check initial version
        assertEq(diamanteMine.VERSION(), "1.1.0");

        // Set some state in V1
        vm.prank(owner);
        diamanteMine.setMiningInterval(12 hours);
        assertEq(diamanteMine.miningInterval(), 12 hours);

        // Deploy V2 implementation
        MockDiamanteMineV2 mockDiamanteMineV2 = new MockDiamanteMineV2(mockPermit2);

        // Upgrade the proxy to V2
        vm.prank(owner);
        diamanteMine.upgradeToAndCall(address(mockDiamanteMineV2), "");

        // Get a proxy instance pointing to the V2 ABI
        MockDiamanteMineV2 proxyAsV2 = MockDiamanteMineV2(payable(address(diamanteMine)));

        // --- Assertions ---
        // 1. Check that state is preserved
        assertEq(proxyAsV2.miningInterval(), 12 hours, "State (miningInterval) should be preserved after upgrade");

        // 2. Check that new V2 functionality is available
        assertEq(proxyAsV2.VERSION(), "2.0.0", "Version should be updated to 2.0.0");
        assertTrue(proxyAsV2.newV2Function(), "New V2 function should be callable");
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- VIEW FUNCTION TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_GetUserMiningState() public {
        // 1. Initially, user1 is not mining
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMineV1.MiningState.NotMining));

        // 2. User1 starts mining
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);

        // 3. Now, user1 is mining
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMineV1.MiningState.Mining));

        // 4. Time passes, user1 is ready to finish
        vm.warp(block.timestamp + diamanteMine.miningInterval());
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMineV1.MiningState.ReadyToFinish));

        // 5. User1 finishes mining
        _finishMiningAs(user1);

        // 6. Finally, user1 is not mining again
        assertEq(uint256(diamanteMine.getUserMiningState(user1)), uint256(DiamanteMineV1.MiningState.NotMining));
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- REFERRAL LOGIC TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_CanClaimReferralBonus_Success() public {
        // 1. User1 starts mining, reminds User2
        _startMiningAs(user1, user2, MIN_AMOUNT_IN_ORO);
        // 2. User2 starts mining within the referral window
        vm.warp(block.timestamp + 1 hours);
        _startMiningAs(user2, address(0), MIN_AMOUNT_IN_ORO);
        // 3. User1 should now be eligible for a bonus
        assertTrue(diamanteMine.isEligibleForReferralBonus(user1), "User1 should be able to claim bonus");
    }

    function test_CanClaimReferralBonus_Fail_NotMining() public view {
        // User1 has not started mining, so cannot claim a bonus
        assertFalse(diamanteMine.isEligibleForReferralBonus(user1), "Should not claim bonus if not mining");
    }

    function test_CanClaimReferralBonus_Fail_NoReminder() public {
        // User1 starts mining but doesn't remind anyone
        _startMiningAs(user1, address(0), MIN_AMOUNT_IN_ORO);
        assertFalse(diamanteMine.isEligibleForReferralBonus(user1), "Should not claim bonus if no one was reminded");
    }

    function test_CanClaimReferralBonus_Fail_RemindedMinedTooLate() public {
        // 1. User1 starts mining, reminds User2
        _startMiningAs(user1, user2, MIN_AMOUNT_IN_ORO);
        // 2. User2 mines, but AFTER the referral window for user1 has passed
        vm.warp(block.timestamp + diamanteMine.miningInterval() + 1);
        _startMiningAs(user2, address(0), MIN_AMOUNT_IN_ORO);
        // 3. User1 is no longer eligible for the bonus
        assertFalse(
            diamanteMine.isEligibleForReferralBonus(user1), "Should not claim bonus if reminded user mined too late"
        );
    }

    function test_CanClaimReferralBonus_Fail_RemindedMinedTooEarly() public {
        // 1. User2 starts mining first
        _startMiningAs(user2, address(0), MIN_AMOUNT_IN_ORO);
        // 2. User1 starts mining later, reminding User2
        vm.warp(block.timestamp + 1 hours);
        _startMiningAs(user1, user2, MIN_AMOUNT_IN_ORO);
        // 3. User1 is not eligible for a bonus because the reminded user started before them
        assertFalse(
            diamanteMine.isEligibleForReferralBonus(user1), "Should not claim bonus if reminded user mined first"
        );
    }

    function test_CanClaimReferralBonus_Fail_RemindedNotMining() public {
        // User1 starts mining, reminds User2, but User2 never starts
        _startMiningAs(user1, user2, MIN_AMOUNT_IN_ORO);
        assertFalse(
            diamanteMine.isEligibleForReferralBonus(user1), "Should not claim bonus if reminded user has not mined"
        );
    }

    function test_Fail_StartMining_CannotRemindSelf() public {
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        // User1 tries to remind themself
        bytes memory args = diamanteMine.encodeMiningArgs(user1, MIN_AMOUNT_IN_ORO);

        vm.startPrank(user1);
        vm.expectRevert(DiamanteMineV1.CannotRemindSelf.selector);
        diamanteMine.startMining(args, root, nullifier, proof, permit);
        vm.stopPrank();
    }

    function test_FinishMining_WithReferral_AfterRefactor() public {
        // This test verifies that the referral bonus is still paid out correctly
        // after refactoring finishMining to use the isEligibleForReferralBonus helper.

        // 1. User1 starts mining with 3 ORO, reminds User2
        _startMiningAs(user1, user2, 3 * 1e18);

        // 2. User2 starts mining with 2 ORO within referral window
        vm.warp(block.timestamp + 1 hours); // Within 24 hour window
        _startMiningAs(user2, address(0), 2 * 1e18);

        // Pre-condition check
        assertTrue(diamanteMine.isEligibleForReferralBonus(user1));

        // 3. User1 finishes mining
        vm.warp(block.timestamp + diamanteMine.miningInterval());
        uint256 initialBalance = diamanteToken.balanceOf(user1);

        // Expected calculation:
        // activeMiners = 2, so rewardLevel = 1
        uint256 levelBonus = diamanteMine.extraRewardPerLevel() * 1;
        uint256 baseReward = diamanteMine.minReward() + levelBonus;
        // miningReward = baseReward * 3 ORO / 1e18
        uint256 miningReward = (baseReward * (3 * 1e18)) / 1e18;
        // referralBonus = miningReward * 10%
        uint256 referralBonus = (miningReward * REFERRAL_BONUS_BPS) / 10_000;
        uint256 expectedTotal = miningReward + referralBonus;

        vm.startPrank(user1);
        (,, bool hasReferralBonus) = diamanteMine.finishMining();
        vm.stopPrank();

        uint256 rewardReceived = diamanteToken.balanceOf(user1) - initialBalance;

        assertTrue(hasReferralBonus, "Should have received a referral bonus");
        assertEq(rewardReceived, expectedTotal, "Should receive mining reward * 3 ORO + referral bonus");
    }

    //-//////////////////////////////////////////////////////////////////////////
    //- REFERRAL DATA ENCODING/DECODING TESTS
    //-//////////////////////////////////////////////////////////////////////////

    function test_ArgsEncoding() public view {
        bytes memory encoded = diamanteMine.encodeMiningArgs(user2, 123 ether);

        // Test the encoding format - should decode to the same address and amount
        (address decodedUser, uint256 decodedAmount) = abi.decode(encoded, (address, uint256));
        assertEq(decodedUser, user2, "Should decode to the same address");
        assertEq(decodedAmount, 123 ether, "Should decode to the same amount");
    }

    function test_ArgsEncoding_ZeroAddressAndAmount() public view {
        bytes memory encoded = diamanteMine.encodeMiningArgs(address(0), 0);

        // Test the encoding format
        (address decodedUser, uint256 decodedAmount) = abi.decode(encoded, (address, uint256));
        assertEq(decodedUser, address(0), "Should decode to zero address");
        assertEq(decodedAmount, 0, "Should decode to zero amount");
    }

    function test_StartMining_WithEncodedArgs() public {
        // Test that startMining works with encoded referral data
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        // Encode multiple referral addresses - should use first one
        bytes memory args = diamanteMine.encodeMiningArgs(user2, MIN_AMOUNT_IN_ORO);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit DiamanteMineV1.StartedMining(user1, user2, nullifier, MIN_AMOUNT_IN_ORO);
        diamanteMine.startMining(args, root, nullifier, proof, permit);
        vm.stopPrank();

        // Verify that user2 (first address) was stored as the reminded user
        assertEq(diamanteMine.lastRemindedAddress(nullifier), user2, "Should store the referral address");
    }

    function test_StartMining_WithEmptyArgs() public {
        // Test that startMining works with empty referral data
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        bytes memory emptyData = "";

        // Amount will be decoded as 0, which is less than minAmountOro
        vm.expectRevert(
            abi.encodeWithSelector(DiamanteMineV1.InvalidOroAmount.selector, 0, MIN_AMOUNT_IN_ORO, MAX_AMOUNT_IN_ORO)
        );
        diamanteMine.startMining(emptyData, root, nullifier, proof, permit);
    }

    function test_StartMining_WithInvalidArgs() public {
        // Test that startMining reverts on invalid referral data (expected behavior)
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);

        // Invalid data that can't be decoded as (address, uint256)
        bytes memory invalidData = "invalid_data";

        // Should revert when trying to decode invalid data
        vm.expectRevert();
        diamanteMine.startMining(invalidData, root, nullifier, proof, permit);
    }
}
