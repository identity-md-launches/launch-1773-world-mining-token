// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldMiningToken} from "../src/WorldMiningToken.sol";

/// @dev Maintains an independent ledger for four test actors while exercising the public ERC-20 API.
contract WorldTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMiningToken private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(WorldMiningToken token_) {
        token = token_;
        actors = [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3")];
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = _validAmount(amountSeed, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include the finite/infinite boundary and approvals larger than the supply.
        uint256 choice = amountSeed % 5;
        uint256 amount = choice == 0
            ? 0
            : choice == 1 ? 1 : choice == 2 ? type(uint256).max - 1 : choice == 3 ? type(uint256).max : amountSeed;

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = _validAmount(amountSeed, allowed < balance ? allowed : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectTransferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        // Infinite approval has no representable overspend; first replace it with a finite one.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            _approve(owner, spender, allowed);
        }
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        // The allowance must survive a failure that happens after the allowance check.
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        if (operation % 3 == 0) {
            _expectFailure(
                owner,
                abi.encodeCall(token.transfer, (address(0), _validAmount(amountSeed, expectedBalance[owner]))),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else if (operation % 3 == 1) {
            uint256 allowed = expectedAllowance[owner][spender];
            uint256 balance = expectedBalance[owner];
            uint256 amount = _validAmount(amountSeed, allowed < balance ? allowed : balance);
            _expectFailure(
                spender,
                abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else {
            _expectFailure(
                owner,
                abi.encodeCall(token.approve, (address(0), amountSeed)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        }
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        _approve(owner, spender, 0);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount)
        );
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = _validAmount(amountSeed, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // The independent ledger stays unchanged: a round trip must return the exact amount.
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _expectFailure(address caller, bytes memory callData, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(callData);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        // No ghost update: all balances and allowances must still match after this handler returns.
    }

    function _validAmount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WorldMiningTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WorldMiningToken private token;
    WorldTokenHandler private handler;

    function setUp() public {
        token = new WorldMiningToken();
        handler = new WorldTokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = WorldTokenHandler.transfer.selector;
        selectors[1] = WorldTokenHandler.approve.selector;
        selectors[2] = WorldTokenHandler.transferFrom.selector;
        selectors[3] = WorldTokenHandler.rejectTransferAboveBalance.selector;
        selectors[4] = WorldTokenHandler.rejectTransferFromAboveAllowance.selector;
        selectors[5] = WorldTokenHandler.rejectTransferFromAboveBalance.selector;
        selectors[6] = WorldTokenHandler.rejectZeroAddress.selector;
        selectors[7] = WorldTokenHandler.revokeAndRejectSpend.selector;
        selectors[8] = WorldTokenHandler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalSupplyEqualsSumOfAllHolderBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_BalancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
        }
    }

    function invariant_AllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev After every random sequence, every holder must still be able to move its entire balance.
    function afterInvariant() public {
        address recipient = handler.actors(0);
        for (uint256 i = 1; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 balance = handler.expectedBalance(owner);
            uint256 recipientBefore = token.balanceOf(recipient);
            vm.prank(owner);
            assertTrue(token.transfer(recipient, balance));
            assertEq(token.balanceOf(owner), 0);
            assertEq(token.balanceOf(recipient), recipientBefore + balance);
        }
        assertEq(token.balanceOf(recipient), SUPPLY);
        address finalRecipient = handler.actors(1);
        vm.prank(recipient);
        assertTrue(token.transfer(finalRecipient, SUPPLY));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(finalRecipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        invariant_AllowancesMatchIndependentLedger();
    }
}
