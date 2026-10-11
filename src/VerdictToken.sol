// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Prediction Markets Run by AI Agents (VERDICT)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 VERDICT (18 decimals) is minted once, in the
///         constructor, to the deployer. Nothing can mint afterwards. Holders may burn their own tokens, and may
///         let an approved spender burn on their behalf, so the supply can only ever shrink.
/// @dev Deliberately dependency-free and privilege-free:
///      - no owner, no pause, no blacklist, no fee or tax, no hooks, no upgradeability;
///      - no `delegatecall`, `callcode` or `selfdestruct` anywhere in the bytecode;
///      - transfers move exactly the amount requested, so launch flows (factory -> distributor, seed into the pool
///        manager, claims, swaps) arrive whole;
///      - the contract name is `VerdictToken` (a short Solidity identifier); the long token name is `name()`.
contract VerdictToken {
    // ---------------------------------------------------------------------------------------------
    // Events (ERC-20)
    // ---------------------------------------------------------------------------------------------

    /// @notice Emitted when `value` tokens move from `from` to `to`. Mints come from and burns go to address(0).
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets `spender`'s allowance to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    /// @notice A transfer, approval or burn named address(0) where a real account was required.
    error ZeroAddress();

    /// @notice `account` tried to move or burn `needed` but holds only `available`.
    error InsufficientBalance(address account, uint256 available, uint256 needed);

    /// @notice `spender` tried to spend `needed` of `owner`'s tokens but is allowed only `available`.
    error InsufficientAllowance(address spender, address owner, uint256 available, uint256 needed);

    // ---------------------------------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------------------------------

    /// @notice The token's full name.
    string public constant name = "Prediction Markets Run by AI Agents";

    /// @notice The token's ticker symbol.
    string public constant symbol = "VERDICT";

    /// @notice Minor units per whole token: 18 decimals, like ETH.
    uint8 public constant decimals = 18;

    /// @notice The supply minted at deployment: one billion whole tokens, in minor units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** uint256(decimals);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    /// @notice Tokens in existence. Starts at `INITIAL_SUPPLY` and only ever decreases, through burns.
    uint256 public totalSupply;

    /// @notice Tokens held by each account.
    mapping(address account => uint256) public balanceOf;

    /// @notice How much `spender` may still move out of `owner`'s balance. `type(uint256).max` is unlimited.
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the entire supply to the deployer. Takes no arguments and calls no other contract, so it can
    ///         be deployed by a factory on an empty chain. There is no other way to create tokens.
    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // ERC-20
    // ---------------------------------------------------------------------------------------------

    /// @notice Moves `amount` tokens from the caller to `to`.
    /// @dev Reverts on a zero recipient or an insufficient balance; never returns false.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Lets `spender` move up to `amount` of the caller's tokens.
    /// @dev Overwrites any previous allowance. Callers who want to change a non-zero allowance safely should set it
    ///      to zero first, or use the amount-relative helpers below.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Moves `amount` tokens from `from` to `to` using the caller's allowance.
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Raises `spender`'s allowance by `added`, immune to the approve front-running race.
    function increaseAllowance(address spender, uint256 added) external returns (bool) {
        _approve(msg.sender, spender, allowance[msg.sender][spender] + added);
        return true;
    }

    /// @notice Lowers `spender`'s allowance by `subtracted`.
    /// @dev Reverts if the current allowance is below `subtracted`, so a reduction can never silently become zero.
    function decreaseAllowance(address spender, uint256 subtracted) external returns (bool) {
        uint256 current = allowance[msg.sender][spender];
        if (current < subtracted) revert InsufficientAllowance(spender, msg.sender, current, subtracted);
        unchecked {
            _approve(msg.sender, spender, current - subtracted);
        }
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Burning
    // ---------------------------------------------------------------------------------------------

    /// @notice Destroys `amount` of the caller's own tokens, shrinking the supply.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Destroys `amount` of `from`'s tokens using the caller's allowance.
    /// @dev This is the only way a third party can reduce someone else's balance, and it needs that holder's explicit
    ///      approval. No deployer, owner or factory privilege bypasses the allowance.
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            balanceOf[from] = fromBalance - amount;
            // The supply is fixed at INITIAL_SUPPLY and only shrinks, so a balance can never exceed it and the sum
            // of two balances cannot overflow.
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (spender == address(0)) revert ZeroAddress();
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = allowance[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance(spender, owner, current, amount);
        unchecked {
            allowance[owner][spender] = current - amount;
        }
        emit Approval(owner, spender, current - amount);
    }

    function _burn(address from, uint256 amount) private {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            balanceOf[from] = fromBalance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
