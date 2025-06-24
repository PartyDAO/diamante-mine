// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DiamanteMine} from "src/DiamanteMine.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockWorldID} from "./mocks/MockWorldID.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

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

    function setUp() public {
        vm.startPrank(owner);
        // Deploy mock tokens
        oroToken = new MockERC20("ORO Token", "ORO");
        diamanteToken = new MockERC20("Diamante Token", "DIAMANTE");

        // Deploy mock World ID
        mockWorldID = new MockWorldID();

        // Deploy DiamanteMine contract
        diamanteMine =
            new DiamanteMine(address(oroToken), address(diamanteToken), mockWorldID, "app_test", "action_test", owner);

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
        diamanteMine.startMining(root, nullifier, proof, user2);

        assertEq(oroToken.balanceOf(user1), (1000 - 1) * 1e18, "User1 ORO balance should decrease by 1");
        assertEq(oroToken.balanceOf(address(diamanteMine)), 1 * 1e18, "Contract ORO balance should increase by 1");
        assertTrue(diamanteMine.userToLastMiningTimestamp(nullifier) > 0, "Mining timestamp should be set");
        assertEq(diamanteMine.userToLastRemindedAddress(nullifier), user2, "Reminded address should be set to user2");
    }

    function test_FinishMining_Success_NoBonus() public {
        // 1. User1 starts mining
        vm.prank(user1);
        (uint256 root, uint256 nullifier, uint256[8] memory proof) = _getProof(user1);
        diamanteMine.startMining(root, nullifier, proof, address(0));

        // 2. Time passes
        vm.warp(block.timestamp + diamanteMine.MINING_INTERVAL() + 1);

        // 3. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);
        diamanteMine.finishMining();
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        assertEq(
            finalDiamanteBalance,
            initialDiamanteBalance + diamanteMine.baseRewardAmount(),
            "User1 should receive base reward"
        );
    }

    function test_FinishMining_Success_WithBonus() public {
        // 1. User1 starts mining, reminds User2
        vm.prank(user1);
        (uint256 root1, uint256 nullifier1, uint256[8] memory proof1) = _getProof(user1);
        diamanteMine.startMining(root1, nullifier1, proof1, user2);

        // Advance time so the timestamps are different
        vm.warp(block.timestamp + 1);

        // 2. User2 starts mining within the window
        vm.prank(user2);
        (uint256 root2, uint256 nullifier2, uint256[8] memory proof2) = _getProof(user2);
        diamanteMine.startMining(root2, nullifier2, proof2, address(0));

        // 3. Time passes for User1's session to end
        vm.warp(block.timestamp + diamanteMine.MINING_INTERVAL() + 1);

        // 4. User1 finishes mining
        uint256 initialDiamanteBalance = diamanteToken.balanceOf(user1);
        vm.prank(user1);
        diamanteMine.finishMining();
        uint256 finalDiamanteBalance = diamanteToken.balanceOf(user1);

        uint256 expectedReward = diamanteMine.baseRewardAmount() * diamanteMine.boostMultiplier() / 100;
        assertEq(finalDiamanteBalance, initialDiamanteBalance + expectedReward, "User1 should receive boosted reward");
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
        vm.expectRevert(DiamanteMine.MustWaitBetweenSessions.selector);
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
        vm.expectRevert(DiamanteMine.MiningSessionNotOver.selector);
        diamanteMine.finishMining();
    }

    function test_AdminFunctions() public {
        vm.startPrank(owner);
        // Set Base Reward
        uint256 newReward = 2 * 1e18;
        diamanteMine.setBaseRewardAmount(newReward);
        assertEq(diamanteMine.baseRewardAmount(), newReward, "Base reward should be updated");

        // Withdraw ORO
        oroToken.mint(address(diamanteMine), 1e18);
        uint256 initialOwnerOro = oroToken.balanceOf(owner);
        diamanteMine.withdrawTokens(address(oroToken), 1e18);
        assertEq(oroToken.balanceOf(owner), initialOwnerOro + 1e18, "Owner should receive ORO");
        vm.stopPrank();
    }

    function test_Fail_AdminFunctions_FromNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        diamanteMine.setBaseRewardAmount(2 * 1e18);

        vm.prank(user1);
        vm.expectRevert();
        diamanteMine.withdrawTokens(address(oroToken), 1);
    }
}
