// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "src/VerdictToken.sol";
import {VerdictTokenHandler} from "./handlers/VerdictTokenHandler.sol";

abstract contract VerdictTokenInvariantBase is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    VerdictTokenHandler internal handler;
    VerdictToken internal token;

    function _setUp(bool withBurns) internal {
        handler = new VerdictTokenHandler(withBurns);
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](withBurns ? 11 : 9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.increaseAllowance.selector;
        selectors[3] = handler.decreaseAllowance.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.rejectBalanceOverspend.selector;
        selectors[6] = handler.rejectAllowanceOverspend.selector;
        selectors[7] = handler.rejectZeroAddress.selector;
        selectors[8] = handler.rejectAllowanceArithmetic.selector;
        if (withBurns) {
            selectors[9] = handler.burn.selector;
            selectors[10] = handler.burnFrom.selector;
        }
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        handler.assertLedger();
    }

    function invariant_balancesAndPermissionsMatchTheLedger() public view {
        handler.assertLedger();
    }

    function invariant_onlyAuthorizedBurnsChangeTheOriginalSupply() public view {
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertLe(handler.burned(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY - handler.burned());
        assertEq(token.name(), "Prediction Markets Run by AI Agents");
        assertEq(token.symbol(), "VERDICT");
        assertEq(token.decimals(), 18);
    }

    /// @dev At the end of every random sequence each holder can still move its entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(i, 0, 2); // Amount seed 2 selects the full balance.
            assertEq(token.balanceOf(handler.actors(i)), 0, "holder could not empty its account");
        }
        assertEq(token.balanceOf(handler.actors(0)), token.totalSupply() - token.balanceOf(address(token)));
        handler.assertLedger();
    }
}

/// @dev Expected failures are caught and checked inside the handler; any escaping revert is a test failure.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract VerdictTokenInvariantTest is VerdictTokenInvariantBase {
    function setUp() public {
        _setUp(true);
    }

    /// @dev Deterministic reachability check: the campaign can exercise nonzero transfers and both burn paths.
    function test_handlerExercisesStateChangesAndExpectedReverts() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(1, 2, 3, 1);
        handler.burn(3, 1);
        handler.burnFrom(0, 1, 1);
        handler.approve(1, 3, 1); // Infinite permission.
        handler.burnFrom(1, 3, 1);
        handler.rejectBalanceOverspend(0, 1, 0, 2);
        handler.rejectBalanceOverspend(0, 1, 0, 3);
        handler.rejectAllowanceOverspend(1, 2, 0, false);
        handler.rejectAllowanceOverspend(1, 2, 0, true);
        handler.rejectZeroAddress(0, 1, 1, 1);
        handler.rejectAllowanceArithmetic(2, 3, 0, true);
        handler.rejectAllowanceArithmetic(2, 3, 0, false);
        assertEq(handler.nonzeroTransfers(), 2);
        assertEq(handler.nonzeroBurns(), 3);
        assertEq(handler.burned(), 3);
        assertEq(handler.rejectedCalls(), 7);
        handler.assertLedger();
    }
}

/// @dev Without successful burns or passive recipients, all supply stays available for long transfer sequences.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract VerdictTokenTransferInvariantTest is VerdictTokenInvariantBase {
    function setUp() public {
        _setUp(false);
    }

    function invariant_transfersAndApprovalsKeepTheFullBillionTokens() public view {
        assertEq(handler.burned(), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
