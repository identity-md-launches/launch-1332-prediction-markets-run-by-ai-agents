// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "src/VerdictToken.sol";

/// @notice Boundary values, authorization isolation, atomic failures and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract VerdictTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    uint256 private constant MAX = type(uint256).max;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    VerdictToken private token;
    address private alice = makeAddr("adversarial-alice");
    address private bob = makeAddr("adversarial-bob");
    address private carol = makeAddr("adversarial-carol");

    function setUp() public {
        token = new VerdictToken();
    }

    function test_constructorCreditsCallerRatherThanTransactionOrigin() public {
        vm.prank(alice, bob);
        VerdictToken fresh = new VerdictToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_zeroValueOperationsFromEmptyHoldersEmitAndPreserveState() public {
        bytes32 beforeState = _state();

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), 0);
        vm.prank(alice);
        token.burn(0);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, carol, 0);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(carol);
        assertTrue(token.transferFrom(alice, bob, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, carol, 0);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), 0);
        vm.prank(carol);
        token.burnFrom(alice, 0);
        assertEq(_state(), beforeState);
    }

    function test_zeroRecipientAndSpenderAreRejectedEvenForZeroAmounts() public {
        bytes32 beforeState = _state();
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.transfer(address(0), 0);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.transferFrom(alice, address(0), 0);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.approve(address(0), 0);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.increaseAllowance(address(0), 0);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.decreaseAllowance(address(0), 0);
        assertEq(_state(), beforeState);
    }

    function test_oneMinorUnitTransferAndBurnShareOneAllowance() public {
        assertTrue(token.transfer(alice, 2));
        vm.prank(alice);
        assertTrue(token.approve(bob, 2));
        vm.startPrank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), 1);
        token.burnFrom(alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY - 1);
        _assertRevoked(alice, bob);
    }

    function test_burningWholeSupplyLeavesZeroAndCannotBeRepeated() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(0), SUPPLY);
        token.burn(SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, address(this), 0, 1));
        token.burn(1);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, address(this), 0, 1));
        token.transfer(alice, 1);
        token.burn(0);
        assertTrue(token.transfer(alice, 0));
        assertEq(_state(), beforeState);
    }

    function test_delegatedBurnCanConsumeExactlyTheEntireSupplyAndPermission() public {
        assertTrue(token.approve(bob, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), bob, 0);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(0), SUPPLY);
        vm.prank(bob);
        token.burnFrom(address(this), SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(0)), 0);
        _assertRevoked(address(this), bob);
    }

    function test_maxUintBalanceOperationsRevertWithoutOverflowOrStateChanges() public {
        bytes memory expected =
            abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, address(this), SUPPLY, MAX);
        bytes32 beforeState = _state();
        vm.expectRevert(expected);
        token.transfer(alice, MAX);
        vm.expectRevert(expected);
        token.burn(MAX);
        assertEq(_state(), beforeState);

        assertTrue(token.approve(bob, MAX));
        beforeState = _state();
        vm.startPrank(bob);
        vm.expectRevert(expected);
        token.transferFrom(address(this), carol, MAX);
        vm.expectRevert(expected);
        token.burnFrom(address(this), MAX);
        vm.stopPrank();
        assertEq(_state(), beforeState);
    }

    function test_onlyExactMaxUintAllowanceIsUnlimited() public {
        assertTrue(token.approve(bob, MAX - 1));
        vm.startPrank(bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        token.burnFrom(address(this), 1);
        vm.stopPrank();
        assertEq(token.allowance(address(this), bob), MAX - 3);

        assertTrue(token.increaseAllowance(bob, 3));
        vm.startPrank(bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        token.burnFrom(address(this), 1);
        vm.stopPrank();
        assertEq(token.allowance(address(this), bob), MAX);

        assertTrue(token.decreaseAllowance(bob, 1));
        vm.prank(bob);
        token.burnFrom(address(this), 1);
        assertEq(token.allowance(address(this), bob), MAX - 2);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 5);
        assertEq(token.totalSupply(), SUPPLY - 3);
    }

    function test_revocationStopsTransfersAndBurnsAfterUnlimitedApprovalWasUsed() public {
        assertTrue(token.transfer(alice, 5));
        vm.prank(alice);
        assertTrue(token.approve(bob, MAX));
        vm.startPrank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        token.burnFrom(alice, 1);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), MAX);
        vm.prank(alice);
        assertTrue(token.approve(bob, 0));
        _assertRevoked(alice, bob);

        vm.prank(alice);
        assertTrue(token.increaseAllowance(bob, 1));
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        _assertRevoked(alice, bob);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(carol), 2);
        assertEq(token.totalSupply(), SUPPLY - 1);
    }

    function test_holderNeedsSelfApprovalForDelegatedEntryPoints() public {
        assertTrue(token.transfer(alice, 2));
        _assertRevoked(alice, alice);
        vm.startPrank(alice);
        assertTrue(token.approve(alice, 2));
        assertTrue(token.transferFrom(alice, bob, 1));
        token.burnFrom(alice, 1);
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY - 1);
    }

    function test_delegatedFullSupplySelfTransferStillConsumesFinitePermission() public {
        assertTrue(token.approve(bob, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), bob, 0);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
        bytes32 beforeState = _state();
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(_state(), beforeState);
    }

    function test_permissionIsSpecificToBothOwnerAndSpender() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(carol, 10));
        vm.prank(alice);
        assertTrue(token.approve(bob, 5));
        _assertRevoked(carol, bob);
        _assertRevoked(alice, carol);
        _assertRevoked(alice, address(this)); // The deployer has no exemption.
        assertEq(token.allowance(alice, bob), 5);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(carol), 10);
    }

    function test_tokenItselfCanReceiveTheWholeSupplyWithoutTaxOrBurn() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_emptyHolderCanGrantAndRevokeMaxPermissionWithoutCreatingTokens() public {
        vm.startPrank(alice);
        assertTrue(token.increaseAllowance(bob, MAX));
        assertEq(token.allowance(alice, bob), MAX);
        bytes32 approvedState = _state();
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        token.increaseAllowance(bob, 1);
        assertEq(_state(), approvedState);
        assertTrue(token.decreaseAllowance(bob, MAX));
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresAllState(uint256 allocation, uint256 amount) public {
        allocation = bound(allocation, 0, SUPPLY);
        amount = bound(amount, 0, allocation);
        assertTrue(token.transfer(alice, allocation));
        assertTrue(token.transfer(bob, SUPPLY - allocation));
        bytes32 beforeState = _state();
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(_state(), beforeState, "transfer round trip changed state");
    }

    function testFuzz_allowanceIncreaseDecreaseRoundTrip(uint256 initial, uint256 added) public {
        added = bound(added, 0, MAX - initial);
        assertTrue(token.approve(bob, initial));
        bytes32 beforeState = _state();
        assertTrue(token.increaseAllowance(bob, added));
        assertTrue(token.decreaseAllowance(bob, added));
        assertEq(_state(), beforeState, "inverse allowance changes did not restore state");
    }

    function testFuzz_approvalOverwritesAndIsIdempotent(uint256 initial, uint256 replacement) public {
        assertTrue(token.approve(carol, 7));
        vm.startPrank(alice);
        assertTrue(token.approve(bob, initial));
        assertTrue(token.approve(bob, replacement));
        assertEq(token.allowance(alice, bob), replacement);
        bytes32 afterReplacement = _state();
        assertTrue(token.approve(bob, replacement));
        vm.stopPrank();
        assertEq(_state(), afterReplacement);
        assertEq(token.allowance(address(this), carol), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAndBurnCannotReuseSpentPermission(uint256 budget, uint256 transferred) public {
        budget = bound(budget, 1, SUPPLY);
        transferred = bound(transferred, 0, budget);
        uint256 destroyed = budget - transferred;
        assertTrue(token.approve(bob, budget));
        vm.startPrank(bob);
        assertTrue(token.transferFrom(address(this), alice, transferred));
        token.burnFrom(address(this), destroyed);
        vm.stopPrank();
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.balanceOf(alice), transferred);
        assertEq(token.totalSupply(), SUPPLY - destroyed);
        _assertRevoked(address(this), bob);
    }

    function testFuzz_delegatedBalanceFailureRollsBackPermission(
        uint256 held,
        uint256 allowed,
        uint256 attempted,
        bool burning
    ) public {
        held = bound(held, 0, SUPPLY - 1);
        allowed = bound(allowed, held + 1, MAX);
        attempted = bound(attempted, held + 1, allowed);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(bob, allowed));
        bytes32 beforeState = _state();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, alice, held, attempted));
        if (burning) token.burnFrom(alice, attempted);
        else token.transferFrom(alice, carol, attempted);
        assertEq(_state(), beforeState, "failed delegated operation left a state change");
    }

    function testFuzz_insufficientPermissionRevertsDespiteSufficientBalance(
        uint256 held,
        uint256 allowed,
        uint256 attempted,
        bool burning
    ) public {
        held = bound(held, 1, SUPPLY);
        allowed = bound(allowed, 0, held - 1);
        attempted = bound(attempted, allowed + 1, held);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(bob, allowed));
        bytes32 beforeState = _state();
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, bob, alice, allowed, attempted)
        );
        if (burning) token.burnFrom(alice, attempted);
        else token.transferFrom(alice, carol, attempted);
        assertEq(_state(), beforeState);
    }

    function testFuzz_allowanceArithmeticFailureIsAtomic(uint256 initial, uint256 delta, bool increasing) public {
        initial = bound(initial, increasing ? 1 : 0, increasing ? MAX : MAX - 1);
        delta = bound(delta, increasing ? MAX - initial + 1 : initial + 1, MAX);
        assertTrue(token.approve(bob, initial));
        bytes32 beforeState = _state();
        if (increasing) {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
            token.increaseAllowance(bob, delta);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, bob, address(this), initial, delta)
            );
            token.decreaseAllowance(bob, delta);
        }
        assertEq(_state(), beforeState);
    }

    function testFuzz_burningInPiecesMatchesOneBurn(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        uint256 snapshot = vm.snapshotState();
        token.burn(first);
        token.burn(second);
        bytes32 splitState = _state();
        assertTrue(vm.revertToStateAndDelete(snapshot));
        token.burn(first + second);
        assertEq(_state(), splitState, "splitting a burn changed its economic effect");
        assertEq(token.totalSupply(), SUPPLY - first - second);
    }

    function testFuzz_delegatedTransfersHandleEveryActorAlias(
        uint8 ownerIndex,
        uint8 spenderIndex,
        uint8 recipientIndex,
        uint256 amount,
        bool unlimited
    ) public {
        address[4] memory actors = [address(this), alice, bob, carol];
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 4));
        }
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        address recipient = actors[recipientIndex % 4];
        amount = bound(amount, 0, SUPPLY / 4);
        vm.prank(owner);
        assertTrue(token.approve(spender, unlimited ? MAX : amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        for (uint256 i; i < actors.length; ++i) {
            uint256 expected = SUPPLY / 4;
            if (actors[i] == owner) expected -= amount;
            if (actors[i] == recipient) expected += amount;
            assertEq(token.balanceOf(actors[i]), expected);
        }
        assertEq(token.allowance(owner, spender), unlimited ? MAX : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientRevertsWithoutConsumingPermission(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, MAX);
        assertTrue(token.approve(bob, allowed));
        bytes32 beforeState = _state();
        vm.prank(bob);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.transferFrom(address(this), address(0), amount);
        assertEq(_state(), beforeState);
    }

    function _assertRevoked(address owner, address spender) private {
        bytes32 beforeState = _state();
        bytes memory expected =
            abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, spender, owner, 0, 1);
        vm.startPrank(spender);
        vm.expectRevert(expected);
        token.transferFrom(owner, carol, 1);
        vm.expectRevert(expected);
        token.burnFrom(owner, 1);
        vm.stopPrank();
        assertEq(_state(), beforeState, "unauthorized operation changed state");
    }

    /// @dev Snapshot all observable mutable state reachable by this fixture, not just the expected error field.
    function _state() private view returns (bytes32 digest) {
        address[5] memory actors = [address(this), alice, bob, carol, address(0)];
        digest = keccak256(abi.encode(token.totalSupply(), token.balanceOf(address(token))));
        for (uint256 i; i < actors.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(actors[i])));
            for (uint256 j; j < actors.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(actors[i], actors[j])));
            }
        }
    }
}
