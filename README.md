# LiiBorrow

A pooled crypto-backed lending smart contract built on top of Aave V3. LiiBorrow aggregates users volatile assets like WETH and WBTC deposits as collateral, supplies them to Aave, and enables users to borrow USDC against their collateral which is off-ramped and received in their local fiat currency. The debt remains in USDC and repayments can be made directly in USDC or in local fiat currency that is onramped to USDC. 

## Overview

LiiBorrow is a Collateralized Debt Position (CDP) protocol that provides decentralized lending services with the following features:

- **Pooled Deposits**: Aggregates users deposits into a single Aave position
- **Fiat Borrowing**: Users borrow USDC, which is off-ramped to local fiat currency
- **Safety Buffer**: Borrowing limits are set 10% below the pool-level Aave's LTV to maintain protocol solvency
- **Automated Liquidation**: Pool-level health factor enforcement with proportional liquidation
- **Debt Shares**: ERC20-like accounting shares for precise debt tracking

## Architecture

### Core Contracts

| Contract | Description |
|----------|-------------|
| `DebtManager.sol` | Main CDP protocol contract handling deposits, borrows, repayments, and liquidations |
| `Aave.sol` | Facade contract for Aave V3 protocol interactions |
| `ErrorsLib.sol` | Custom error definitions |
| `EventsLib.sol` | Event definitions for on-chain tracking |
| `Types.sol` | Custom type definitions |

### Supported Assets

- **Collateral**: Starting with WETH (Wrapped Ether), WBTC (Wrapped Bitcoin)
- **Debt**: USDC (USD Coin), expand to USDT (Tether USD) later

## Protocol Mechanics

### Deposit Flow

1. User calls `depositCollateralERC20()` or `depositCollateralETH()`
2. Collateral tokens are transferred to the protocol
3. Collateral is supplied to Aave V3 Pool
4. User's collateral balance is updated internally

### Borrow Flow

1. User calls `borrowUsdc()` with desired amount
2. Protocol validates health factor (must remain >= 1.0)
3. Protocol borrows USDC from Aave on behalf of users
4. USDC is transferred to a PSP (Payment Service Provider) and the borrower receives local fiat currency
5. Debt shares are minted to track the user's debt

### Repay Flow

1. User calls `repayUsdc()` with repayment amount
2. Protocol takes its cut (APR spread) from the repayment
3. Remaining amount is used to repay Aave debt
4. Debt shares are burned proportionally

### Liquidation Flow

1. Monitor detects user with health factor < 1.0
2. Liquidator calls `liquidate()` with repayment amount
3. Up to 50% of debt can be repaid in a single liquidation
4. Protocol seizes collateral + liquidation bonus
5. Liquidation fee is applied to seized collateral

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MIN_HEALTH_FACTOR` | 1.0 | Minimum health factor (below = liquidatable) |
| `DANGER_ZONE` | 1.1 | Health factor threshold for risky positions |
| `CLOSE_FACTOR` | 50% | Maximum debt that can be repaid in liquidation |
| `PLATFORM_AAVE_LTV_DIFF` | 10% | Safety buffer below Aave's LTV |
| `BASE_APR` | 0.5% | Minimum protocol APR markup |
| `BASE_BONUS` | 1% | Base liquidation bonus for liquidators |
| `MAX_COOLDOWN` | 30 minutes | Maximum cooldown period between actions |

## Precision Conventions

- **USD values**: 1e18 = 1 USD (wad)
- **USD prices from oracle**: 1e8 = 1 USD
- **Percentages**: 1e4 = 100%
- **APR/Fees**: 1e18 = 100% (wad)

## Smart Contract Functions

### User Functions

```solidity
// Deposit collateral (ERC20)
function depositCollateralERC20(address tokenCollateralAddress, uint256 amountCollateral)

// Deposit collateral (Native ETH)
function depositCollateralETH(uint256 amountCollateral)

// Redeem/withdraw collateral
function redeemCollateral(address collateral, uint256 amountCollateral, bool isEth)

// Borrow USDC
function borrowUsdc(uint256 amountToBorrow)

// Repay USDC debt
function repayUsdc(uint256 amountToRepay)

// Liquidate undercollateralized position
function liquidate(address user, address debtAsset, address collateralAsset, uint256 repayAmount, bool isEth)
```

### Admin Functions

```solidity
// Set protocol APR markup
function setProtocolAPRMarkup(uint256 _newAPR)

// Set liquidation fee
function setLiquidationFee(uint256 _newFee)

// Set cooldown period
function setCoolDownPeriod(uint256 _newCoolDown)

// Add new collateral asset
function addCollateralAsset(address collateral)

// Pause/unpause collateral activity
function pauseCollateralActivity(address collateral)
function unPauseCollateralActivity(address collateral)

// Pause/unpause entire protocol
function pause()
function unpause()

// Withdraw protocol revenue
function withdrawRevenue(address to, address asset, uint256 amount)
```

### View Functions

```solidity
// Get user's health factor and status
function getUserHealthFactor(address user) returns (uint256 healthFactor, HealthStatus status)

// Check if user is liquidatable
function isLiquidatable(address user) returns (bool)

// Get user's maximum borrow amount
function getUserMaxBorrow(address user) returns (uint256 value, uint256 amount)

// Get user's collateral balance
function getCollateralBalanceOfUser(address user, address token) returns (uint256)

// Get user's debt
function getUserDebt(address user) returns (uint256 userAaveDebt, uint256 userTotalDebt)

// Get platform LTV and LLTV
function getPlatformLltvAndLtv() returns (uint256 lltv, uint256 ltv)

// Get supported collateral tokens
function getCollateralTokens() returns (address[] memory)
```

## Security Considerations

### Reentrancy Protection
All state-changing functions use OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks.

### Access Control
Admin functions are protected by OpenZeppelin's `Ownable` contract, restricting critical operations to the protocol owner.

### Health Factor Checks
- Pre-borrow validation ensures health factor >= 1.0
- Post-operation validation reverts if health factor drops below minimum
- Aave-level validation prevents borrowing beyond available liquidity

### Cooldown Period
A configurable cooldown period (default: 10 minutes) between user actions prevents rapid position changes and flash loan attacks.

### Safety Buffer
The protocol maintains a 10% buffer below Aave's LTV (PLATFORM_AAVE_LTV_DIFF), providing additional protection against liquidation scenarios.

## Building and Testing

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) - Ethereum development framework
- [Solidity](https://docs.soliditylang.org/) ^0.8.20

### Install Dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Run Tests

```bash
forge test
```

## Deployment

### Testnet (Sepolia)

```bash
# Set environment variables in .env
SEPOLIA_RPC_URL=<your_rpc_url>
PRIVATE_KEY_DEPLOYER=<your_private_key>
ETHERSCAN_API_KEY=<your_etherscan_key>

# Deploy to Sepolia
make deploy-config ARGS="--network sepolia"
make deploy ARGS="--network sepolia"
```

### Mainnet

```bash
# Set environment variables in .env
MAINNET_RPC_URL=<your_rpc_url>
PRIVATE_KEY_DEPLOYER=<your_private_key>
ETHERSCAN_API_KEY=<your_etherscan_key>

# Deploy to Mainnet
make deploy-config ARGS="--network mainnet"
make deploy ARGS="--network mainnet"
```

### Tenderly Virtual Testnet

Tenderly Virtual Testnets provide a fast, fork-based testing environment with real mainnet state.

```bash
# Set environment variables in .env
TENDERLY_VIRTUAL_TESTNET_ADMIN=<your_admin_url>
TENDERLY_VIRTUAL_TESTNET_RPC_URL=<your_tenderly_rpc_url>
TENDERLY_VERIFIER_URL=<your_tenderly_verifier_url>
TENDERLY_ACCESS_KEY=<your_access_key>

# Deploy to Tenderly Virtual Testnet
make deploy-config ARGS="--network tenderly"
make deploy ARGS="--network tenderly"
```
> **Note**: - Comment and uncomment the NETWORK_ARGS and RPC_URL depending on where you are deploying.

> **Note**: - After deployment record the contract addresse in HelperConfig file.

### Interact with protocol

```bash
## SIMULATE CONTRACTS TO ESTIMATE GAS AND FIX BUGS

# Deploy mocks and configure
make sim-deployConfig

# Deploy DebtManager
make sim-deploy

# Interact with protocol
make sim-supply
make sim-borrow
make sim-repay
make sim-withdraw

## SEND REAL TX
make supply
make borrow
make repay
make withdraw
```

## Integrations

### Aave V3

The protocol integrates with Aave V3 for:
- Supplying collateral (aToken receipts)
- Borrowing USDC (variable rate)
- Repaying debt
- Withdrawing collateral
- Reading oracle prices and reserve data

### Price Oracles

Asset prices are fetched from Aave's oracle system, which aggregates data from multiple sources for price accuracy.

## Risk Disclosure

- **Smart Contract Risk**: Smart contracts are subject to vulnerabilities despite rigorous testing
- **Liquidation Risk**: Users whose health factor drops below 1.0 are subject to liquidation
- **Oracle Risk**: Price oracle failures or manipulation could affect protocol operations
- **Interest Rate Risk**: Variable borrowing rates on Aave may increase unexpectedly
- **Protocol Risk**: The protocol maintains a buffer below Aave's LTV, but extreme market conditions could lead to undercollateralization

## License

MIT License - see [LICENSE](./LICENSE) for details

## Acknowledgments

- [Aave Protocol](https://aave.com/) - Lending protocol integration
- [OpenZeppelin](https://openzeppelin.com/) - Smart contract security libraries
- [Foundry](https://foundry.sh/) - Smart contract development framework
