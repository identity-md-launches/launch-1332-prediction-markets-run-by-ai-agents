// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @title Deploy script for VerdictToken
/// @notice Reviewable, manual deployment path. The IdentityMD launch does not use this script: the launch factory
///         deploys the token from its built creation code with no constructor arguments and receives the whole
///         supply. This script exists so a reviewer or the requester can reproduce the deployment on a fork or a
///         testnet and so tests can exercise the exact deployment logic.
/// @dev The token takes no configuration: name, symbol, decimals and supply are compile-time constants. `deploy()`
///      is a plain function the tests call directly; `run()` only wraps it in a broadcast.
contract DeployVerdictToken is Script {
    /// @notice Deploys the token. Whoever executes this (the broadcaster, or the test contract) receives the supply.
    function deploy() public returns (VerdictToken token) {
        token = new VerdictToken();
    }

    /// @notice Broadcasts the deployment with the signer `forge script` was given (`--private-key`, `--ledger`, ...).
    function run() external returns (VerdictToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
