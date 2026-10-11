// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";
import {DeployVerdictToken} from "../script/DeployVerdictToken.s.sol";

/// @notice Stands in for the launch factory: deploys the token with CREATE2 the way the factory does, so the supply
///         lands in the factory's balance, then moves it on to the distributor, the pool and the requester.
contract FactoryStandIn {
    function deploy(bytes memory creationCode, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(deployed != address(0), "create2 failed");
    }

    function move(VerdictToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice Launch-flow tests: the exact amounts the IdentityMD launch moves (swarm 10%, pool 70%, remainder 20%)
///         arrive whole, the pool-side counterparty can take and return tokens via allowances, and the deployment
///         script's function behaves like the raw constructor.
contract LaunchFlowsTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;
    uint256 constant SWARM_BPS = 1_000;
    uint256 constant POOL_BPS = 7_000;

    FactoryStandIn factory;
    VerdictToken token;
    address distributor = makeAddr("distributor");
    address poolManager = makeAddr("poolManager");
    address remainderTo = makeAddr("remainderTo");
    address claimant = makeAddr("claimant");
    address trader = makeAddr("trader");

    function setUp() public {
        factory = new FactoryStandIn();
        token = VerdictToken(factory.deploy(type(VerdictToken).creationCode, bytes32(uint256(1))));
    }

    function test_create2DeploymentMintsWholeSupplyToTheFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    function test_creationCodeTakesNoConstructorArguments() public {
        // Deploying the raw creation code with no appended arguments succeeds and mints to whoever deploys it.
        address at = factory.deploy(type(VerdictToken).creationCode, bytes32(uint256(2)));
        assertEq(VerdictToken(at).balanceOf(address(factory)), SUPPLY);
        assertEq(VerdictToken(at).totalSupply(), SUPPLY);
    }

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, distributor, swarm));
        assertEq(token.balanceOf(distributor), swarm);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullLaunchSplitArrivesExactly() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        factory.move(token, distributor, swarm);
        factory.move(token, poolManager, pool);
        factory.move(token, remainderTo, remainder);

        assertEq(token.balanceOf(distributor), 100_000_000 ether);
        assertEq(token.balanceOf(poolManager), 700_000_000 ether);
        assertEq(token.balanceOf(remainderTo), 200_000_000 ether);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_poolCounterpartyCanPullViaAllowanceAndPayOut() public {
        // A swap router / pool manager pulls tokens from a trader through transferFrom and pays out with transfer.
        // Neither leg may lose a unit, otherwise the pool's accounting reverts.
        factory.move(token, trader, 1_000 ether);
        vm.prank(trader);
        token.approve(poolManager, 1_000 ether);

        vm.prank(poolManager);
        token.transferFrom(trader, poolManager, 1_000 ether);
        assertEq(token.balanceOf(poolManager), 1_000 ether);
        assertEq(token.balanceOf(trader), 0);

        vm.prank(poolManager);
        token.transfer(trader, 1_000 ether);
        assertEq(token.balanceOf(trader), 1_000 ether);
        assertEq(token.balanceOf(poolManager), 0);
    }

    function test_factoryCannotPullBackWhatItHandedOut() public {
        factory.move(token, claimant, 1 ether);
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.InsufficientAllowance.selector, address(factory), claimant, 0, 1)
        );
        token.transferFrom(claimant, address(factory), 1);
    }

    function test_deployScriptFunctionMintsToItsCaller() public {
        DeployVerdictToken script = new DeployVerdictToken();
        VerdictToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY, "the script's caller context received the supply");
        assertEq(deployed.name(), "Prediction Markets Run by AI Agents");
        assertEq(deployed.symbol(), "VERDICT");
        assertEq(deployed.decimals(), 18);
    }

    function test_contractIdentifierFitsTheManifest() public pure {
        // The launch records the Solidity name in 32 bytes.
        assertLe(bytes("VerdictToken").length, 32);
    }
}
