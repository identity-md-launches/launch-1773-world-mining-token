// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMiningToken} from "src/WorldMiningToken.sol";

/// @dev Complements the original deployment and ERC-20 tests with boundary and authorization sequences.
/// forge-config: default.fuzz.runs = 1024
contract WorldMiningTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMiningToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new WorldMiningToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_OneBaseUnitCanBeTransferredAndSpent() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsEvenToSelf() public {
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(alice, type(uint256).max);
        vm.expectRevert(error);
        token.transfer(address(this), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_MaximumFiniteAllowanceDecreasesOnEverySpend() public {
        uint256 allowance = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowance));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), allowance - 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), allowance - SUPPLY);
        _assertBalances(0, 1, SUPPLY - 1);
    }

    function test_ExhaustedAllowanceCannotBeUsedAgain() public {
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);

        // A zero transfer remains valid, but must not restore the exhausted approval.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 0));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 2, 2, 0);
    }

    function test_InfiniteApprovalCanBeRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_ApprovalReplacementAfterPartialSpendUsesOnlyNewLimit() public {
        assertTrue(token.approve(spender, 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertTrue(token.approve(spender, 7));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 7, 8));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 8);
        assertEq(token.allowance(address(this), spender), 7);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 47, 47, 0);
    }

    function test_TransferFromByHolderRequiresAndConsumesSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        _assertBalances(SUPPLY, 0, 0);

        assertTrue(token.approve(address(this), 2));
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(SUPPLY - 2, 2, 0);
    }

    function test_AnAllowanceCannotBeRedelegated() public {
        assertTrue(token.approve(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), alice), 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_TransferredTokensDoNotCarryTheSendersAllowances() public {
        assertTrue(token.approve(spender, 5));
        assertTrue(token.transfer(alice, 5));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(address(this), spender), 5);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - 5, 5, 0);
    }

    function test_AllowanceAuthorizationUsesCallerRatherThanTransactionOrigin() public {
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 10);
        _assertBalances(SUPPLY, 0, 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 9);
        assertEq(token.allowance(address(this), bob), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_ApprovalDoesNotReserveFundsAndSurvivesAnEmptyBalance() public {
        assertTrue(token.approve(spender, 100));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 100));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 100);
        assertEq(token.allowance(address(this), spender), 100);
        _assertBalances(0, SUPPLY, 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), 100));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 100));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, SUPPLY - 100, 100);
    }

    function test_ZeroSpenderIsRejectedForZeroAndMaximumApprovals() public {
        assertTrue(token.approve(spender, 17));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 17);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ZeroDelegatedTransferToZeroRevertsWithFiniteAndInfiniteApprovals() public {
        assertTrue(token.approve(spender, 17));
        _rejectZeroReceiver(0);
        assertEq(token.allowance(address(this), spender), 17);
        assertTrue(token.approve(spender, type(uint256).max));
        _rejectZeroReceiver(0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_MaximumDelegatedTransferFailsForBalanceDespiteInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_FailedDelegatedTransferPreservesBalanceAndApproval(
        uint256 balance,
        uint256 amount,
        uint256 approved,
        bool toSelf
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, toSelf ? alice : bob, amount);

        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(SUPPLY - balance, balance, 0);
    }

    function testFuzz_ApprovalReplacementUsesLastValue(uint256 first, uint256 last, uint256 amount) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, last));
        assertEq(token.allowance(address(this), spender), last);
        amount = bound(amount, 0, last < SUPPLY ? last : SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), last == type(uint256).max ? last : last - amount);
        _assertBalances(SUPPLY - amount, amount, 0);
    }

    function testFuzz_InvalidReceiverPreservesAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        _rejectZeroReceiver(amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_RoundTripRestoresBalancesWithoutChangingApprovals(
        uint256 aliceBalance,
        uint256 amount,
        uint256 approved
    ) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        amount = bound(amount, 0, aliceBalance);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, SUPPLY - aliceBalance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(bob);
        assertTrue(token.approve(spender, type(uint256).max));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        _assertBalances(0, aliceBalance - amount, SUPPLY - aliceBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        _assertBalances(0, aliceBalance, SUPPLY - aliceBalance);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(bob, spender), type(uint256).max);
    }

    function _rejectZeroReceiver(uint256 amount) private {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
