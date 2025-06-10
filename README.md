# StabilityVault Contract

## Overview

The `StabilityVault` smart contract is a DeFi yield optimization vault that interacts with:

- A **Stability Pool**
- A **V3 DEX Router** (e.g., PancakeSwap V3)
- The **Dolomite Margin protocol**

It is built using upgradeable patterns and relies on OpenZeppelin libraries for security, access control, and token
utilities. The contract allows users to deposit a designated `depositToken` (like PUSD), compounds rewards earned from
collateral assets, and maximizes returns via yield strategies and automated token swaps.

## Features

### ✅ Core Vault Mechanics

- **Deposit:** Moves `depositToken` into the Stability Pool and simultaneously deploys it into Dolomite for extra yield.
- **Withdraw:** Supports withdrawal from both on-chain balance and invested allocations (Stability Pool and Dolomite),
  enforcing reentrancy protection.
- **Compound Gains:** Automatically converts earned `collateralAssets` into `baseToken`, then into `depositToken`, and
  reinvests.
- **Harvest:** Collects rewards without full compounding to refresh the vault’s balance.
- **Rebalance:** Fully closes and resets positions by withdrawing and redepositing assets.

### 🛠️ Configuration & Management

- **Add Collateral Assets:** Dynamically allows a manager to add new reward assets with their Chainlink price oracles.
- **Set Swap Pools:** Configurable swap paths for each token pair using V3 DEX pools.
- **Update Allocation:** Reconfigures what portion of capital is allocated to the Stability Pool.
- **Add Oracles:** Additional oracles for new assets can be plugged in by the manager.

### 🔁 Yield Integration (Dolomite)

- **onYield:** Deposits assets into Dolomite Margin via `DepositWithdrawalRouter`.
- **offYield:** Withdraws assets from Dolomite.
- **Market ID Handling:** Automatically fetches market IDs based on the `depositToken`.

### 📉 Liquidation Functionality

- **Trove Liquidation:** Interacts with `IVesselManagerOperations` to liquidate undercollateralized positions.

### 📊 Reporting and Analytics

- **balanceOf:** Reports total vault value (SP, Dolomite, gains, and liquid balances).
- **balanceOfSp:** Reports current deposits in the Stability Pool.
- **balanceOfDepositToken:** Reports idle token balance.
- **balaceOfGains:** Converts unclaimed collateral rewards to USD equivalent.
- **balanceOfYield:** Checks current Dolomite Margin holdings.

### 🔒 Security & Access Control

- **Role Separation:**
  - `vault`: For triggering deposits/withdrawals.
  - `manager`: For administrative functions like adding assets, updating pools, or pausing.
- **Pausable:** Can pause all major operations in emergencies.
- **ReentrancyGuard:** Prevents reentrancy attacks on sensitive functions like `withdraw`.

### 🔁 Swapping & Price Conversion

- **\_swapV3In:** Uses configured PancakeSwap V3 pools to perform token swaps.
- **tokenAToTokenBConversion:** Estimates output amount of one token in terms of another using oracle prices.
- **getPrice:** Fetches token price from its oracle.

### ⚙️ Upgradeability

- **Initializable:** Uses OpenZeppelin’s upgradeable contract pattern.
- **UUPSUpgradeable:** Ensures authorized upgrades via `_authorizeUpgrade`.

### 🧾 Allowances Management

- **\_giveAllowances:** Approves all relevant protocols (StabilityPool, DEX, Dolomite) to pull tokens.
- **\_removeAllowances:** Revokes approvals when needed.
- Handles allowances dynamically for each newly added collateral asset.

## 🧩 Integration Contracts

The `StabilityVault` interacts with the following interfaces:

| Interface                  | Purpose                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| `IStabilityPool`           | Interface for depositing to and withdrawing from the Stability Pool, and claiming rewards. |
| `IV3SwapRouter`            | Interface for performing token swaps using PancakeSwap V3-style routers.                   |
| `IDolomiteMargin`          | Interface for interacting with Dolomite's lending/borrowing margin protocol.               |
| `IDepositWithdrawalRouter` | Router interface to deposit/withdraw assets into Dolomite markets.                         |
| `ITroveManagerOperations`  | Used to liquidate Troves (undercollateralized positions) in the system.                    |
| `IPriceFeed`               | Chainlink-style oracle interface to fetch token price feeds.                               |
| `IPancakeV3Pool`           | Provides access to liquidity pool parameters, such as swap fees.                           |

