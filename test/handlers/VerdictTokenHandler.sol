// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "src/VerdictToken.sol";

/// @notice A closed population of four holders plus the token itself as a passive recipient.
/// @dev The ledger starts from the specified allocation and changes only by requested, successful
///      operations. It is never resynchronized from the token's balances or allowances.
contract VerdictTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint256 private constant MAX = type(uint256).max;

    VerdictToken public immutable token;
    bool public immutable includeTokenRecipient;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public burned;
    uint256 public nonzeroTransfers;
    uint256 public nonzeroBurns;
    uint256 public rejectedCalls;
    uint256 private previousSupply = SUPPLY;

    constructor(bool includeTokenRecipient_) {
        includeTokenRecipient = includeTokenRecipient_;
        actors[0] = address(this); // The actual constructor caller remains an ordinary holder.
        actors[1] = makeAddr("invariant-alice");
        actors[2] = makeAddr("invariant-bob");
        actors[3] = makeAddr("invariant-carol");
        token = new VerdictToken();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            if (i != 0) assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        // Seed usable delegated permissions; later calls freely overwrite and revoke them.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], SUPPLY / actors.length);
        }
    }

    modifier supplyNeverIncreases() {
        _;
        uint256 current = token.totalSupply();
        assertLe(current, previousSupply, "a call increased supply");
        previousSupply = current;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external supplyNeverIncreases {
        address from = _actor(fromSeed);
        address to = _recipient(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external supplyNeverIncreases {
        // Explicitly sample revocation, unlimited approval, and its adjacent finite value.
        uint256 mode = amountSeed % 5;
        uint256 amount = mode == 0 ? 0 : mode == 1 ? MAX : mode == 2 ? MAX - 1 : amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function increaseAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 current = expectedAllowance[owner][spender];
        uint256 amount = _amount(amountSeed, MAX - current);
        vm.prank(owner);
        assertTrue(token.increaseAllowance(spender, amount));
        expectedAllowance[owner][spender] = current + amount;
    }

    function decreaseAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 current = expectedAllowance[owner][spender];
        uint256 amount = _amount(amountSeed, current);
        vm.prank(owner);
        assertTrue(token.decreaseAllowance(spender, amount));
        expectedAllowance[owner][spender] = current - amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 limit = _spendLimit(owner, spender);
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _consumeAllowance(owner, spender, amount);
        _move(owner, to, amount);
    }

    function burn(uint256 ownerSeed, uint256 amountSeed) external supplyNeverIncreases {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        vm.prank(owner);
        token.burn(amount);
        _destroy(owner, amount);
    }

    function burnFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external supplyNeverIncreases {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, _spendLimit(owner, spender));
        vm.prank(spender);
        token.burnFrom(owner, amount);
        _consumeAllowance(owner, spender, amount);
        _destroy(owner, amount);
    }

    /// @dev All four balance-consuming entry points must reject, even when allowance is sufficient.
    ///      A failed delegated call must roll back its tentative allowance debit as well.
    function rejectBalanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, MAX);
        operation %= 4;
        bytes memory data;
        address caller = owner;
        if (operation == 0) {
            data = abi.encodeCall(token.transfer, (spender, amount));
        } else if (operation == 1) {
            data = abi.encodeCall(token.burn, (amount));
        } else {
            _approve(owner, spender, amount);
            caller = spender;
            data = operation == 2
                ? abi.encodeCall(token.transferFrom, (owner, spender, amount))
                : abi.encodeCall(token.burnFrom, (owner, amount));
        }
        _reject(caller, data, abi.encodeWithSelector(VerdictToken.InsufficientBalance.selector, owner, balance, amount));
    }

    function rejectAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed, bool burning)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = bound(allowanceSeed, 0, SUPPLY);
        _approve(owner, spender, allowed);
        uint256 amount = allowed + 1;
        bytes memory data = burning
            ? abi.encodeCall(token.burnFrom, (owner, amount))
            : abi.encodeCall(token.transferFrom, (owner, spender, amount));
        _reject(
            spender,
            data,
            abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, spender, owner, allowed, amount)
        );
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[owner]);
        operation %= 5;
        bytes memory data;
        address caller = owner;
        if (operation == 0) {
            data = abi.encodeCall(token.transfer, (address(0), amount));
        } else if (operation == 1) {
            _approve(owner, spender, amount);
            caller = spender;
            data = abi.encodeCall(token.transferFrom, (owner, address(0), amount));
        } else if (operation == 2) {
            data = abi.encodeCall(token.approve, (address(0), amount));
        } else if (operation == 3) {
            data = abi.encodeCall(token.increaseAllowance, (address(0), amount));
        } else {
            data = abi.encodeCall(token.decreaseAllowance, (address(0), 0));
        }
        _reject(caller, data, abi.encodeWithSelector(VerdictToken.ZeroAddress.selector));
    }

    function rejectAllowanceArithmetic(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool increasing)
        external
        supplyNeverIncreases
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 current = expectedAllowance[owner][spender];
        if (increasing) {
            if (current == 0) {
                current = 1;
                _approve(owner, spender, current);
            }
            uint256 amount = bound(amountSeed, MAX - current + 1, MAX);
            _reject(
                owner,
                abi.encodeCall(token.increaseAllowance, (spender, amount)),
                abi.encodeWithSignature("Panic(uint256)", 0x11)
            );
        } else {
            if (current == MAX) {
                current = MAX - 1;
                _approve(owner, spender, current);
            }
            uint256 amount = bound(amountSeed, current + 1, MAX);
            _reject(
                owner,
                abi.encodeCall(token.decreaseAllowance, (spender, amount)),
                abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, spender, owner, current, amount)
            );
        }
    }

    /// @notice Compare every balance and permission in the closed population, including untouched pairs.
    function assertLedger() external view {
        uint256 sum = token.balanceOf(address(token));
        assertEq(sum, expectedBalance[address(token)], "passive token recipient balance");
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, expectedBalance[owner], "holder balance differs from requested flows");
            sum += balance;
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                assertEq(
                    token.allowance(owner, spender), expectedAllowance[owner][spender], "permission ledger differs"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained permission");
            assertEq(token.allowance(address(0), owner), 0, "zero holder gained permission");
            assertEq(token.allowance(address(token), owner), 0, "passive recipient granted permission");
        }
        assertEq(token.balanceOf(address(0)), 0, "zero address owns tokens");
        assertEq(sum, token.totalSupply(), "balances do not add up to circulating supply");
        assertEq(sum + burned, SUPPLY, "tokens were created or lost");
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _recipient(uint256 seed) private view returns (address) {
        if (!includeTokenRecipient) return _actor(seed);
        uint256 index = seed % (actors.length + 1);
        return index == actors.length ? address(token) : actors[index];
    }

    /// @dev Pin zero, one minor unit and the whole available amount alongside ordinary bounded values.
    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        uint256 mode = seed % 6;
        if (mode == 0 || limit == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return limit;
        return bound(seed, 0, limit);
    }

    function _spendLimit(address owner, address spender) private view returns (uint256) {
        uint256 balance = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        return balance < allowed ? balance : allowed;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _consumeAllowance(address owner, address spender, uint256 amount) private {
        if (expectedAllowance[owner][spender] != MAX) expectedAllowance[owner][spender] -= amount;
    }

    function _move(address from, address to, uint256 amount) private {
        // Self-transfers preserve the holder's balance, including full-balance transfers.
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
        if (amount != 0) ++nonzeroTransfers;
    }

    function _destroy(address owner, uint256 amount) private {
        expectedBalance[owner] -= amount;
        burned += amount;
        if (amount != 0) ++nonzeroBurns;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(returned, expectedError, "invalid operation returned the wrong error");
        ++rejectedCalls;
        // No ghost change: the invariant must find every tentative write rolled back.
    }
}
