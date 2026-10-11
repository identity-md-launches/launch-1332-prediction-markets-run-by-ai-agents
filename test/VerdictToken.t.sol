// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @notice Unit tests for VerdictToken: metadata, the one-time mint, transfers, allowances, burns and the absence of
///         any privileged path. Each test deploys its own token, uses no environment variables and depends on no
///         particular caller, so the suite passes in any order and in parallel.
contract VerdictTokenTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    VerdictToken token;
    address deployer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        deployer = address(this);
        token = new VerdictToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and the constructor mint
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Prediction Markets Run by AI Agents");
        assertEq(token.symbol(), "VERDICT");
        assertEq(token.decimals(), 18);
    }

    function test_constructorMintsWholeSupplyToDeployerOnce() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        VerdictToken fresh = new VerdictToken();

        assertEq(fresh.INITIAL_SUPPLY(), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0, "nobody but the deployer is allocated anything");
    }

    function test_supplyIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.balanceOf(deployer), token.totalSupply());
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether));

        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY, "a transfer must not change the supply");
    }

    function test_transferOfZeroSucceeds() public {
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferToSelfIsANoOp() public {
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 5 ether));
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_transferWholeBalanceLeavesZero() public {
        token.transfer(alice, 7 ether);
        vm.prank(alice);
        token.transfer(bob, 7 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 7 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, alice, 1 ether, 1 ether + 1));
        token.transfer(bob, 1 ether + 1);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 42);
        assertTrue(token.approve(alice, 42));
        assertEq(token.allowance(deployer, alice), 42);
    }

    function test_approveOverwritesPreviousAllowance() public {
        token.approve(alice, 42);
        token.approve(alice, 7);
        assertEq(token.allowance(deployer, alice), 7);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowanceAndEmits() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 6 ether);

        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 2 ether);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, carol, 4 ether);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 4 ether));

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.balanceOf(carol), 4 ether);
        assertEq(token.balanceOf(bob), 0, "the spender receives nothing itself");
        assertEq(token.allowance(alice, bob), 2 ether);
    }

    function test_transferFromWithUnlimitedAllowanceDoesNotDecrement() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, carol, 3 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 3 ether);
    }

    function test_transferFromRevertsOnInsufficientAllowance() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 1 ether);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, bob, alice, 1 ether, 1 ether + 1)
        );
        token.transferFrom(alice, carol, 1 ether + 1);
    }

    function test_transferFromRevertsWithoutAnyAllowance() public {
        token.transfer(alice, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, bob, alice, 0, 1));
        token.transferFrom(alice, carol, 1);
    }

    function test_transferFromRevertsOnInsufficientBalanceEvenWithAllowance() public {
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 5 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, alice, 1 ether, 2 ether));
        token.transferFrom(alice, carol, 2 ether);
        assertEq(token.allowance(alice, bob), 5 ether, "a reverted call must not consume allowance");
    }

    function test_transferFromRevertsToZeroAddress() public {
        token.approve(alice, 1);
        vm.prank(alice);
        vm.expectRevert(VerdictToken.ZeroAddress.selector);
        token.transferFrom(deployer, address(0), 1);
    }

    function test_increaseAndDecreaseAllowance() public {
        assertTrue(token.increaseAllowance(alice, 5));
        assertEq(token.allowance(deployer, alice), 5);
        assertTrue(token.increaseAllowance(alice, 3));
        assertEq(token.allowance(deployer, alice), 8);
        assertTrue(token.decreaseAllowance(alice, 6));
        assertEq(token.allowance(deployer, alice), 2);
    }

    function test_decreaseAllowanceRevertsBelowZero() public {
        token.approve(alice, 2);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, alice, deployer, 2, 3));
        token.decreaseAllowance(alice, 3);
    }

    function test_increaseAllowanceRevertsOnOverflow() public {
        token.approve(alice, type(uint256).max);
        vm.expectRevert();
        token.increaseAllowance(alice, 1);
    }

    // ---------------------------------------------------------------------------------------------
    // burn / burnFrom
    // ---------------------------------------------------------------------------------------------

    function test_burnShrinksSupplyAndBalance() public {
        token.transfer(alice, 10 ether);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), 4 ether);
        vm.prank(alice);
        token.burn(4 ether);

        assertEq(token.balanceOf(alice), 6 ether);
        assertEq(token.totalSupply(), SUPPLY - 4 ether);
    }

    function test_burnRevertsOnInsufficientBalance() public {
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, alice, 1 ether, 2 ether));
        token.burn(2 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_burnFromSpendsAllowance() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 5 ether);

        vm.prank(bob);
        token.burnFrom(alice, 5 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY - 5 ether);
    }

    function test_burnFromRevertsWithoutAllowanceEvenForDeployer() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, deployer, alice, 0, 1));
        token.burnFrom(alice, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_burnFromRevertsOnInsufficientAllowance() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        token.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, bob, alice, 1, 2));
        token.burnFrom(alice, 2);
    }

    // ---------------------------------------------------------------------------------------------
    // No privilege, no mint, no dangerous opcodes
    // ---------------------------------------------------------------------------------------------

    /// @dev Mirrors the launch floor: none of the common admin selectors exist, so none can grow the supply, from a
    ///      stranger or from the deployer.
    function test_noCommonAdminCallIncreasesSupply() public {
        address attacker = makeAddr("attacker");
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    /// @dev Mirrors the launch floor: nothing the deployer can call moves or freezes another holder's balance.
    function test_noPrivilegedHandMovesOrFreezesAHolder() public {
        token.transfer(alice, SUPPLY / 1_000);
        uint256 held = token.balanceOf(alice);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        vm.prank(deployer);
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, alice, deployer, 1));
        assertFalse(moved, "the deployer must not be able to pull without allowance");
        assertEq(token.balanceOf(alice), held);

        vm.prank(alice);
        assertTrue(token.transfer(bob, held / 2));
        assertEq(token.balanceOf(bob), held / 2);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    function test_rejectsEtherAndUnknownCalls() public {
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token has no receive function");
        (ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "the token has no fallback");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: conservation and arithmetic edges
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(to), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, deployer, SUPPLY, amount));
        token.transfer(alice, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, allowed);
        token.approve(bob, allowed);
        vm.prank(bob);
        token.transferFrom(deployer, carol, spent);
        assertEq(token.balanceOf(carol), spent);
        if (allowed != type(uint256).max) assertEq(token.allowance(deployer, bob), allowed - spent);
    }

    function testFuzz_burnOnlyEverShrinksSupply(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        token.burn(first);
        token.burn(second);
        assertEq(token.totalSupply(), SUPPLY - first - second);
        assertEq(token.balanceOf(deployer), SUPPLY - first - second);
    }
}
