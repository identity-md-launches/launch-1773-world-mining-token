# World Mining Token (WORLD)

WORLD is a fixed-supply ERC-20. Its constructor mints the entire supply once to
the immediate deployer (`msg.sender`). It uses the unmodified OpenZeppelin
Contracts v5.4.0 ERC-20 implementation, with no additional transfer rules.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `WorldMiningToken` |
| Source | `src/WorldMiningToken.sol` |
| Token name | `World Mining Token` |
| Symbol | `WORLD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None; ABI arguments are empty (`0x`) |
| Initial recipient | Immediate deployer, which is the launch factory for this launch |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, `200` runs |
| Metadata bytecode hash | `none` |

There are no application contracts, linkable external libraries, constructor
dependencies, initialization calls, configurable addresses, or post-deployment
settings. The constructor makes no external calls. It works with both CREATE and
CREATE2. Deployment through a helper contract sends the supply to that helper;
neither the transaction origin nor the caller of the factory receives it directly.

The launch operator should use the creation bytecode for
`src/WorldMiningToken.sol:WorldMiningToken`, built with the checked-in configuration.
It is available in `out/WorldMiningToken.sol/WorldMiningToken.json`, or through:

```sh
forge inspect src/WorldMiningToken.sol:WorldMiningToken bytecode
```

The separate launch process supplies the manifest and handles deployment and
distribution. This project requires no wallet, private key, RPC endpoint, or
environment configuration to build or test. No transactions are sent by this project.

## Behavior and assumptions

- The requested token is a standard ERC-20. The word "Mining" in its name does
  not add mining rewards, staking, or subsequent issuance.
- Every successful transfer credits exactly the amount debited, without fees,
  burns, rebasing, recipient callbacks, or address-specific exemptions.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with OpenZeppelin's ERC-6093 custom errors on invalid operations. A revert
  rolls back all changes, including allowance spending.
- Zero-value transfers between nonzero addresses are valid and emit `Transfer`.
  Self-transfers are valid when the sender has sufficient balance. Transfers to
  the zero address and approvals to the zero address revert.
- `approve` replaces the caller's allowance for a spender; zero revokes it.
  Finite allowances decrease on `transferFrom`. The maximum `uint256` allowance
  is treated as unlimited and does not decrease. Even a holder calling
  `transferFrom` on itself needs an allowance for positive amounts.
- Minting emits one `Transfer` from the zero address during construction.
  Transfers emit `Transfer`, and explicit approvals emit `Approval`.
  OpenZeppelin v5 does not emit another `Approval` when `transferFrom` spends
  an allowance; integrations should query `allowance` for its current value.
- There is no owner, minter, pauser, blacklist, seizure function, public burn,
  proxy, upgrade mechanism, or administrative recovery function. The deployer
  receives tokens but has no privileged control over other holders.

## Operational responsibilities

The factory is responsible for distributing its initial balance. Under the
supplied launch terms, 10% goes to the launch distributor, 88% seeds the pool,
and the remaining 2% goes to the requester-specified recipient. WORLD itself
does not allocate tokens or implement the pool, pricing, fees, or claims. Those
are external launch responsibilities; ordinary ERC-20 transfers deliver exact
amounts to those destinations.

Before release, the launch operator should verify the selected artifact and
build settings, initial supply and factory balance, manifest parameters, and
the launch's full pool integration. Publish verified source and the deployed
address through the launch process. Independent adversarial review remains a
release responsibility; local tests are not a security audit.

After launch, there are no administrative settings or scheduled maintenance.
Holders control transfers and approvals. Use only trusted spenders and limited
allowances where possible. When changing an existing nonzero approval, first
revoke it, wait for confirmation, and then grant the new amount to reduce the
standard ERC-20 allowance replacement race. Revocation cannot undo spending
that already occurred. Lost keys and transfers to inaccessible addresses
(including the token contract itself) cannot be recovered by an administrator.

## Build and verification

All Solidity dependencies are vendored as ordinary files in `lib/`. Their versions,
upstream archive URLs, licenses, and SHA-256 digests are recorded in
[`lib/DEPENDENCIES.md`](lib/DEPENDENCIES.md). There is no dependency installation
step. Foundry and the pinned Solidity compiler must be available to the runner;
with those installed, builds and tests need no network. FFI and filesystem
permissions are not enabled.

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xed17dc0146e50717ebb55c855d5a0580934a7b258bf58d44ed53971f0afd3fa5 forge test
forge fmt --check
```

The tests use no environment variables, forks, wall-clock delays, filesystem
cheatcodes, or external services. Test addresses are local fixtures only.

- `test/WorldMiningToken.t.sol` covers metadata, constructor mint logs, CREATE2
  factory receipt, exact distribution/claim transfers, transfer and approval
  events, zero and self transfers, finite/unlimited allowances, revocation,
  rejected transfers, rollback on failure, absent privileged functions, runtime
  size/opcodes, and four fuzz properties with 1,024 cases each.
- `test/WorldMiningToken.invariant.t.sol` runs randomized sequences of transfers,
  approvals, and delegated transfers across four holders. It compares balances
  and allowances against an independent ledger and checks supply conservation.
  Each of the three invariants runs 256 sequences of 64 calls, with unexpected
  reverts treated as failures.

The distribution test models token movements only. It does not deploy the
Uniswap PoolManager or prove swap/pricing behavior. The supplied protected
integration tests depend on the separate launch harness, its infrastructure,
and launch parameters; they are not part of the standalone test suite.

### Local check results

Verified with Foundry `1.8.3` and Solidity `0.8.26`:

- `forge build`: passed.
- `forge test` with the seed above: 31 tests passed, zero failures or skips.
  This runner counts the three invariants as one grouped test: 256 sequences,
  16,384 handler calls, zero reverts. All four fuzz tests passed 1,024 cases each.
- `forge fmt --check`: passed.
- Artifact inspection: 2,649 bytes of creation code and 1,753 bytes of runtime;
  no unresolved library links; the ABI exposes only the ERC-20 functions,
  metadata, and `INITIAL_SUPPLY`, with a zero-argument constructor.
- Dependency integrity: all 36 vendored source/license files matched the
  recorded SHA-256 digests after formatting and compilation.

The local code review checked that minting is reachable only during construction,
balance movement requires the holder or an allowance, failed delegated transfers
are atomic, and the token makes no external calls. No owner, upgrade, oracle,
signature, or reentrancy mechanism is needed for this implementation. Slither,
Mythril, and the external protected launch harness were not run locally.
