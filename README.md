# Prediction Markets Run by AI Agents (VERDICT)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum mainnet.

| Property | Value |
| --- | --- |
| Solidity contract | `VerdictToken` (`src/VerdictToken.sol`) |
| `name()` | `Prediction Markets Run by AI Agents` |
| `symbol()` | `VERDICT` |
| `decimals()` | `18` |
| Total supply | `1,000,000,000` VERDICT = `1000000000000000000000000000` minor units |
| Minting | Once, in the constructor, the whole supply to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None |
| Transfer fee or tax | None |
| Burning | `burn(uint256)` by the holder, `burnFrom(address,uint256)` with the holder's allowance |

## Layout

```
foundry.toml                 solc 0.8.26, optimizer on, bytecode_hash = "none", no ffi, no fs access
remappings.txt               forge-std/ -> lib/forge-std/src/
src/VerdictToken.sol         the token
script/DeployVerdictToken.s.sol  reviewable manual deploy script (not used by the launch)
test/VerdictToken.t.sol      unit tests: metadata, mint, transfers, allowances, burns, no privilege
test/LaunchFlows.t.sol       launch-flow tests: CREATE2 from a factory, 10/70/20 split arrives whole
lib/forge-std/               forge-std v1.9.6, vendored as plain files (no submodule)
```

## Build and test

```
forge build
forge test
forge fmt --check
```

Tests use no environment variables, no forks and no fixed caller, so they pass in any order and in
parallel. The only dependency is forge-std, committed under `lib/`, so the project builds offline
once solc 0.8.26 is available.

## Design and assumptions

- **Fixed supply.** `INITIAL_SUPPLY` is a compile-time constant. The constructor sets `totalSupply`
  and credits the deployer. There is no `mint`, no minter role, no owner and no upgrade path, so the
  supply can never grow. Burns reduce it.
- **Plain transfers.** `transfer` and `transferFrom` move exactly the requested amount. There are no
  exemptions because nothing needs exempting: the launch's flows (factory to distributor, seeding
  the Uniswap v4 pool, claims, swaps in both directions) move whole amounts by construction.
- **No privileged hand.** No pause, blacklist, freeze, lock or seize. `burnFrom` is the only way a
  third party can reduce someone else's balance and it requires that holder's allowance, which the
  tests confirm even the deployer cannot bypass.
- **Allowances.** `approve` overwrites. `increaseAllowance` and `decreaseAllowance` are provided for
  callers who want to avoid the approve front-running race. An allowance of `type(uint256).max` is
  unlimited and is not decremented, which is the common convention routers rely on.
- **Reverts, not false.** Failed transfers revert with a typed error (`InsufficientBalance`,
  `InsufficientAllowance`, `ZeroAddress`) instead of returning `false`. Successful calls return
  `true`.
- **No dangerous opcodes.** The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`
  (asserted by a test that walks the bytecode) and has no `receive` or `fallback`, so it cannot
  hold ETH.
- **No external calls.** The contract never calls another contract, so there is no reentrancy
  surface and the constructor can run on an empty chain.
- **Dependency-free.** The token imports nothing. forge-std is vendored for tests only.

## Deployment parameters

The launch is decided by IdentityMD's policy and is not configurable here:

| Parameter | Value |
| --- | --- |
| Chain | Ethereum mainnet (chain id 1) |
| Deployer | the IdentityMD `ProjectFactory`, via `launchCustom` (CREATE2) |
| Token constructor args | none |
| `token.totalSupply` in the manifest | `1000000000000000000000000000` |
| Pair currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Pool share (`economics.poolBps`) | `7000` (70% of supply seeds the pool) |
| Opening market cap (`economics.initialMarketCapWei`) | `2500000000000000000000` (2,500 IMD for the whole supply) |
| Remainder recipient (`economics.remainderTo`) | `0x612a9bb008e16ef2d24f41dae9fc661831d93367` (receives 20%) |
| Swarm share | 10%, forwarded by the factory to the launch's `MerkleDistributor` |

The manifest (`launch.json`) is written by the manifest step after this work is accepted; it is
intentionally not part of this repository.

Because the constructor mints to `msg.sender`, the factory receives all 1,000,000,000 VERDICT and
then pays it out: 10% to the distributor, 70% into the pool, 20% to the remainder address. No
contract here is allocated or reserved any tokens.

### Manual deployment (for review, forks and testnets)

`script/DeployVerdictToken.s.sol` deploys the same creation code with no arguments. Whoever signs
receives the supply. It is a reviewable reproduction path only; this assignment does not authorize
transactions and no key is held or read here.

```
forge script script/DeployVerdictToken.s.sol:DeployVerdictToken \
  --rpc-url <RPC> --broadcast --private-key <KEY>   # or --ledger / --account
```

## After launch

Nothing to configure. The token has no owner-settable values, no roles and no external
dependencies, so there are no setters to call once it is deployed.

## Operational responsibilities

- **Requester / remainder wallet.** `0x612a9bb008e16ef2d24f41dae9fc661831d93367` receives 20% of
  the supply and is responsible for custody of it. Tokens sent to a wrong address cannot be
  recovered by anyone; there is no admin.
- **Holders.** Only a holder (or a spender they approved) can move or burn their balance. Approvals
  of `type(uint256).max` grant unlimited spending until revoked with `approve(spender, 0)`.
- **Explorer verification.** After launch, verify `VerdictToken` on Etherscan with
  `forge verify-contract` using solc 0.8.26, optimizer runs 200, `bytecode_hash = "none"`, and no
  constructor arguments. This belongs to the network's deployer, not to this task.
- **No upgrades, no pause.** If a defect is found after launch, the only remedy is a new token and a
  migration; there is no emergency switch by design.

## Security notes

The eth-security checklist (pinned input) was used as a review list. Items that apply to a plain
token and how they are handled:

- Reentrancy: no external calls, nothing to re-enter.
- Access control: no privileged functions exist, so none can be misconfigured.
- Input validation: zero-address recipients and spenders revert; amounts are checked against
  balance and allowance with typed errors.
- Decimals: fixed at 18, matching the manifest and the pair token.
- Proxies / delegatecall: none, and the tests assert the opcodes are absent.
- Infinite approvals: supported as the convention, documented above for holders.

Tools run: `forge build`, `forge test` (including 256-run fuzz tests), `forge fmt --check`. Slither
and Mythril were not available in this environment and did not run. Tests passing is not an audit;
an independent adversarial review is still recommended before the launch is admitted.

## Licence

MIT. forge-std is MIT/Apache-2.0, see `lib/forge-std/`.
