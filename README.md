# StabilityVault Contract

## Overview

This Solidity smart contract (`StabilityVault.sol`) is designed to interact with a decentralized finance (DeFi)
protocol's Stability Pool. It allows depositing a specific token (`depositToken`, e.g., PUSD), earns rewards in various
`collateralAssets` from the Stability Pool, and automatically compounds these gains by swapping them back into the
`depositToken` via a V3 DEX router (like PancakeSwap V3).

The contract utilizes OpenZeppelin libraries for security (Pausable, ReentrancyGuard), access control (Ownable via
FeeManager), and ERC20 interactions. It's also initializable, suggesting it might be intended for use with upgradeable
proxy patterns.

## Features

- **Deposit:** Deposits the `depositToken` into the associated Stability Pool.
- **Withdraw:** Withdraws the `depositToken` from the contract, potentially pulling from the Stability Pool if needed.
- **Compound Gains:** Automatically swaps accumulated gains (in `collateralAssets`) back to the `depositToken` (via an
  intermediate `baseToken`) and redeposits into the Stability Pool.
- **Harvest:** Claims gains from the Stability Pool and swaps them to `depositToken` for deposit.
- **Collateral Management:** Allows adding/managing supported collateral assets and their corresponding price oracles
  (Chainlink).
- **DEX Integration:** Configurable swap pools for converting tokens using a V3 router.
- **Balance Reporting:** Provides functions to check the total value locked, balance in the Stability Pool, pending
  deposit token balance, and the value of unrealized gains.
- **Liquidation Trigger:** Includes a function to interact with a `TroveManager` to liquidate troves.
- **Pausable:** Contract operations can be paused and unpaused by the manager.
- **Access Control:** Key functions are restricted to a `manager` or a specific `vault` address.
- **Security:** Implements Reentrancy Guard.

### Core Operations of the StabilityVault

The `StabilityVault` contract is centered around managing funds within a DeFi Stability Pool. Key operations include:

- **Depositing Funds:** It takes a primary asset, the `depositToken`, and places it into the designated Stability Pool.
- **Withdrawing Funds:** It allows retrieval of the `depositToken`. If the contract's immediate balance isn't enough, it
  can pull the required amount from its deposit in the Stability Pool.
- **Automated Compounding:** The contract handles gains earned from the Stability Pool, which arrive as various
  `collateralAssets`. It features functions (`compoundGains`, `harvest`) to automatically:
  1.  Claim these collateral rewards.
  2.  Swap the `collateralAssets` back into the main `depositToken` (potentially using an intermediate `baseToken` for
      efficient routing). This swap utilizes an integrated V3 DEX router.
  3.  Re-deposit the acquired `depositToken` back into the Stability Pool to maximize yield.

### Management and Integrations

Beyond core deposit and compounding actions, the contract includes features for administration and interaction with
other protocols:

- **Collateral Asset Management:** A manager role can add new types of `collateralAssets` that the vault should expect
  to receive and handle. This includes associating each asset with its specific Chainlink price `oracle` for value
  calculations.
- **DEX Swap Configuration:** The manager can define the specific V3 liquidity pools (`addPool`) to be used for swapping
  between different tokens (e.g., collateral-to-base, base-to-deposit).
- **External Protocol Interaction:** It contains a `liquidate` function designed to interact with a separate
  `TroveManager` contract, likely to trigger the liquidation of undercollateralized positions within the associated
  lending protocol.

### Utility and Security Aspects

The contract incorporates standard utility and security patterns:

- **Detailed Balance Reporting:** Provides multiple view functions (`balanceOf`, `balanceOfSp`, `balanceOfDepositToken`,
  `balaceOfGains`) allowing users or other contracts to query the total value held, the specific amount within the
  Stability Pool, any `depositToken` held directly by the contract, and the current estimated value of unclaimed gains.
- **Pausable Functionality:** Inherits OpenZeppelin's `Pausable` module, enabling a manager to temporarily halt critical
  functions if necessary.
- **Role-Based Access Control:** Critical functions have restricted access. Actions like depositing and withdrawing are
  typically limited to a specific `vault` address, while administrative tasks (managing assets/pools, pausing,
  triggering compounding) are reserved for a `manager` address.
- **Reentrancy Protection:** Utilizes OpenZeppelin's `ReentrancyGuard` on functions like `withdraw` to mitigate the risk
  of reentrancy attacks.

