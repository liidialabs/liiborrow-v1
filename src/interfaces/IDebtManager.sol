// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Types.sol";

/**
 * @title IDebtManager
 * @notice Interface for the LiiBorrow CDP Protocol
 * @dev Third-party integrators should use these functions to interact with the protocol.
 *      All user-facing functions require the caller to have approved token transfers where applicable.
 *
 * Integration Guide:
 * - For depositing collateral: approve tokens before calling deposit functions
 * - For borrowing: ensure sufficient collateral is deposited first
 * - For repaying: approve USDC before calling repayUsdc
 * - For liquidations: approve USDC and check isLiquidatable() first
 *
 * Precision Conventions:
 * - USD values: 1e18 = 1 USD (wad)
 * - USD prices from oracle: 1e8 = 1 USD
 * - Health factors: 1e18 = 1.0
 * - Percentages: 1e4 = 1%
 */
interface IDebtManager {
    // ================================================
    // EVENTS
    // ================================================

    /// @notice Emitted when collateral is deposited
    /// @param user The account that deposited collateral
    /// @param token The collateral token address (address(0) for ETH)
    /// @param amount Amount of collateral deposited
    event Supply(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when collateral is withdrawn
    /// @param redeemFrom The account whose collateral was redeemed
    /// @param redeemTo The recipient of the redeemed collateral
    /// @param token The collateral token address
    /// @param amount The amount redeemed
    event Withdraw(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when a user position is liquidated
    /// @param liquidator The address that performed the liquidation
    /// @param user The account that was liquidated
    /// @param collateralToken The collateral token seized
    /// @param collateralSeized The amount of collateral seized
    /// @param debtCovered The USDC amount used to repay debt
    /// @param timestamp The block timestamp
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 collateralSeized,
        uint256 debtCovered,
        uint32 timestamp
    );

    /// @notice Emitted when USDC is borrowed
    /// @param user The borrower
    /// @param amount The amount borrowed
    /// @param timestamp The block timestamp
    event Borrow(address indexed user, uint256 amount, uint32 timestamp);

    /// @notice Emitted when USDC is repaid
    /// @param user The repayer
    /// @param amount The amount repaid
    /// @param timestamp The block timestamp
    event RepayUsdc(address indexed user, uint256 amount, uint32 timestamp);

    /// @notice Emitted when protocol revenue is withdrawn
    /// @param treasury The recipient address
    /// @param asset The asset withdrawn
    /// @param amount The amount withdrawn
    /// @param timestamp The block timestamp
    event RevenueWithdrawn(
        address indexed treasury,
        address indexed asset,
        uint256 amount,
        uint32 timestamp
    );

    // ================================================
    // COLLATERAL MANAGEMENT
    // ================================================

    /// @notice Deposit ERC20 tokens as collateral
    /// @dev Requires prior approval of token transfer. Collateral is supplied to Aave.
    /// @param tokenCollateralAddress The ERC20 token to use as collateral
    /// @param amountCollateral Amount to deposit (in token decimals)
    /// @param onBehalfOf Account that will receive the collateral deposit
    function depositCollateralERC20(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address onBehalfOf
    ) external;

    /// @notice Deposit ETH as collateral (wrapped to WETH)
    /// @dev Requires msg.value == amountCollateral. Cannot deposit for address(0).
    /// @param amountCollateral Amount of ETH to deposit (in wei)
    /// @param onBehalfOf Account that will receive the collateral deposit
    function depositCollateralETH(
        uint256 amountCollateral,
        address onBehalfOf
    ) external payable;

    /// @notice Withdraw deposited collateral
    /// @dev Enforces health factor >= 1.0 after withdrawal. Subject to cooldown period.
    /// @param collateral The collateral token to withdraw
    /// @param amountCollateral Amount to withdraw
    /// @param onBehalfOf Account that will receive the withdrawn collateral
    /// @param isEth True to receive as ETH instead of WETH
    function redeemCollateral(
        address collateral,
        uint256 amountCollateral,
        address onBehalfOf,
        bool isEth
    ) external;

    // ================================================
    // DEBT OPERATIONS
    // ================================================

    /// @notice Borrow USDC/USDT against supplied collateral
    /// @dev Borrow amount is capped at maximum allowed by health factor. Subject to cooldown.
    /// @param asset The asset to borrow (USDC or USDT)
    /// @param amountToBorrow Amount to borrow
    /// @param onBehalfOf Account that will receive the borrowed asset
    function borrow(address asset, uint256 amountToBorrow, address onBehalfOf) external;

    /// @notice Repay debt for USDC/USDT
    /// @dev Partial repayments allowed. Excess repayment beyond debt is refunded.
    /// @param asset The asset to repay (USDC or USDT)
    /// @param amountToRepay Amount to repay
    /// @param onBehalfOf Account whose debt will be repaid
    function repay(address asset, uint256 amountToRepay, address onBehalfOf) external;

    // ================================================
    // LIQUIDATION
    // ================================================

    /// @notice Liquidate an undercollateralized user position
    /// @dev User must be liquidatable (HF < 1.0). Max 50% of debt can be repaid per liquidation.
    /// @param user Account to liquidate
    /// @param debtAsset Address of the debt asset (USDC)
    /// @param collateralAsset Collateral token to seize
    /// @param repayAmount Amount of debt to repay (capped at 50% of position)
    /// @param isEth True to receive seized collateral as ETH
    function liquidate(
        address user,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount,
        bool isEth
    ) external;

    // ================================================
    // HEALTH & RISK (View Functions)
    // ================================================

    /// @notice Get user's health factor
    /// @param user Account to check
    /// @return healthFactor Health factor (1e18 = 1.0, below 1.0 is liquidatable)
    /// @return status Health status: 0=Healthy, 1=Danger, 2=Liquidatable
    function getUserHealthFactor(
        address user
    ) external returns (uint256 healthFactor, HealthStatus status);

    /// @notice Get user's LTV (Loan-to-Value ratio)
    /// @param user Account to check
    /// @return ltv LTV ratio in wad (1e18 = 100%)
    function userLTV(address user) external returns (uint256 ltv);

    /// @notice Check if a user is liquidatable
    /// @param user Account to check
    /// @return True if position can be liquidated (HF < 1.0)
    function isLiquidatable(address user) external returns (bool);

    /// @notice Get platform risk parameters
    /// @return lltv Platform liquidation threshold (1e18 = 100%)
    /// @return ltv Platform loan-to-value ratio (1e18 = 100%)
    function getPlatformLltvAndLtv() external returns (uint256 lltv, uint256 ltv);

    // ================================================
    // ACCOUNT VIEW FUNCTIONS
    // ================================================

    /// @notice Get comprehensive account data
    /// @param user Account to query
    /// @return totalCollateral Total collateral value in USD (1e8 = 1 USD)
    /// @return totalDebt Total debt value in USD (1e8 = 1 USD)
    /// @return healthFactor Current health factor
    function getUserAccountData(
        address user
    ) external returns (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 healthFactor
    );

    /// @notice Get user's total collateral value
    /// @param user Account to query
    /// @return totalCollateralValue Total collateral in USD (1e18 = 1 USD)
    function getAccountCollateralValue(
        address user
    ) external view returns (uint256 totalCollateralValue);

    /// @notice Get user's collateral balance for a specific token
    /// @param user Account to query
    /// @param token Collateral token address
    /// @return balance Collateral balance
    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256 balance);

    /// @notice Get all collateral positions for a user
    /// @param user Account to query
    /// @return userCollateral Array of collateral positions
    function getUserSuppliedCollateralAmount(
        address user
    ) external view returns (UserCollateral[] memory userCollateral);

    /// @notice Get user's maximum withdrawal amount for a collateral
    /// @param user Account to query
    /// @param collateral Collateral token address
    /// @return maxAmount Maximum withdrawable amount
    function getUserMaxCollateralWithdrawAmount(
        address user,
        address collateral
    ) external returns (uint256 maxAmount);

    /// @notice Get user's debt position
    /// @param user Account to query
    /// @return aaveDebt Debt owed to Aave (USDC)
    /// @return totalDebt Total debt including protocol fees (USDC)
    function getUserDebt(
        address user
    ) external returns (uint256 aaveDebt, uint256 totalDebt);

    /// @notice Get user's total debt in USD value
    /// @param user Account to query
    /// @return totalUsdcToRepay Total debt in USD (1e18 = 1 USD)
    function getUserTotalDebt(
        address user
    ) external returns (uint256 totalUsdcToRepay);

    /// @notice Get user's debt shares
    /// @param user Account to query
    /// @return shares User's debt shares
    function getUserShares(address user) external view returns (uint256 shares);

    /// @notice Get user's debt shares
    /// @param user Account to query
    /// @return healthFactor Health factor (wad)
    function getHealthFactor(address user) external returns (uint256 healthFactor);

    // ================================================
    // BORROWING LIMITS (View Functions)
    // ================================================

    /// @notice Get maximum borrowable amount for a user
    /// @param user Account to query
    /// @param asset The asset to borrow (USDC or USDT)
    /// @return valueInUsd Maximum borrowable value in USD (1e18 = 1 USD)
    /// @return amount Maximum borrowable amount
    function getUserMaxBorrow(
        address user,
        address asset
    ) external returns (uint256 valueInUsd, uint256 amount);

    // ================================================
    // PRICING & CALCULATIONS (View Functions)
    // ================================================

    /// @notice Get USD value of a token amount
    /// @param token Token address
    /// @param amount Token amount
    /// @return value USD value (1e18 = 1 USD)
    function getUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256 value);

    /// @notice Get on-chain asset price
    /// @param token Token address
    /// @return price Price in USD (1e8 = 1 USD)
    function getAssetPrice(address token) external view returns (uint256 price);

    /// @notice Calculate collateral amount for a given USD value
    /// @param collateral Collateral token address
    /// @param usdValue USD value to convert (1e8 = 1 USD)
    /// @return amount Collateral amount
    function getCollateralAmount(
        address collateral,
        uint256 usdValue
    ) external view returns (uint256 amount);

    /// @notice Calculate collateral to seize in a liquidation
    /// @param collateral Collateral token address
    /// @param debtAsset The debt asset being repaid (USDC or USDT)
    /// @param debtAmount Debt amount being repaid
    /// @return amountToSeize Collateral amount to seize (includes bonus)
    function getCollateralAmountToSeize(
        address collateral,
        address debtAsset,
        uint256 debtAmount
    ) external view returns (uint256 amountToSeize);

    // ================================================
    // PROTOCOL INFO (View Functions)
    // ================================================

    /// @notice Get supported collateral tokens
    /// @return tokens Array of supported collateral token addresses
    function getCollateralTokens() external view returns (address[] memory tokens);

    /// @notice Check if a token is supported as collateral
    /// @param token Token address to check
    /// @return True if supported
    function checkIfTokenSupported(address token) external view returns (bool);

    /// @notice Check if collateral deposits are paused for a token
    /// @param token Token address to check
    /// @return True if paused
    function checkIfCollateralPaused(address token) external view returns (bool);

    /// @notice Get total collateral supplied for a token
    /// @param collateral Token address
    /// @return totalSupplied Total amount supplied
    function getTotalColSupplied(
        address collateral
    ) external view returns (uint256 totalSupplied);

    /// @notice Get platform debt values
    /// @return aaveDebt Total debt owed to Aave
    /// @return totalDebt Total protocol debt
    function getPlatformDebt() external returns (uint256 aaveDebt, uint256 totalDebt);

    /// @notice Get total debt shares
    /// @return Total debt shares across all users
    function getTotalDebtShares() external view returns (uint256);

    /// @notice Get liquidation bonus for a collateral
    /// @param collateral Collateral token address
    /// @return bonus Bonus percentage (wad, e.g., 0.05e18 = 5%)
    function getLiquidationBonus(
        address collateral
    ) external view returns (uint256 bonus);

    /// @notice Get protocol APR markup
    /// @return apr APR in wad (1e18 = 100%)
    function getProtocolAPRMarkup() external view returns (uint256 apr);

    /// @notice Get protocol liquidation fee
    /// @return fee Liquidation fee in wad (1e18 = 100%)
    function getLiquidationFee() external view returns (uint256 fee);

    /// @notice Get cooldown period
    /// @return period Seconds between allowed actions
    function getCoolDownPeriod() external view returns (uint256 period);

    /// @notice Get next allowed activity timestamp for a user
    /// @param user Account to check
    /// @return timestamp Next activity timestamp
    function getNextActivity(address user) external view returns (uint32 timestamp);

    // ================================================
    // REVENUE & EARNINGS (View Functions)
    // ================================================

    /// @notice Get protocol revenue from interest spread
    /// @return Revenue accrued in USDC
    function getProtocolRevenue() external view returns (uint256);

    /// @notice Get liquidation revenue per token
    /// @return earnings Array of liquidation earnings
    function getLiquidationRevenue()
        external
        view
        returns (LiquidationEarnings[] memory earnings);

    /// @notice Get liquidation revenue for specific token
    /// @param asset Token address
    /// @return revenue Accrued revenue
    function getLiquidationRevenueSpecific(
        address asset
    ) external view returns (uint256 revenue);

    // ================================================
    // ADMIN FUNCTIONS (Owner Only)
    // ================================================

    /// @notice Withdraw protocol revenue
    /// @dev Only callable by protocol owner/treasury
    /// @param to Recipient address
    /// @param asset Asset to withdraw
    /// @param amount Amount to withdraw
    function withdrawRevenue(
        address to,
        address asset,
        uint256 amount
    ) external;

    /// @notice Set protocol APR markup
    /// @dev Only owner. Cannot be below base APR (0.5%)
    /// @param newApr New APR in wad (1e18 = 100%)
    function setProtocolAPRMarkup(uint256 newApr) external;

    /// @notice Set liquidation fee
    /// @dev Only owner
    /// @param newFee New fee in wad (1e18 = 100%)
    function setLiquidationFee(uint256 newFee) external;

    /// @notice Set cooldown period
    /// @dev Only owner. Capped at 30 minutes
    /// @param newCooldown New period in seconds
    function setCoolDownPeriod(uint256 newCooldown) external;

    /// @notice Add new collateral token
    /// @dev Only owner. Cannot be address(0)
    /// @param collateral Token address to add
    function addCollateralAsset(address collateral) external;

    /// @notice Pause collateral deposits
    /// @dev Only owner
    /// @param collateral Token to pause
    function pauseCollateralActivity(address collateral) external;

    /// @notice Unpause collateral deposits
    /// @dev Only owner
    /// @param collateral Token to unpause
    function unPauseCollateralActivity(address collateral) external;

    /// @notice Pause all protocol operations
    /// @dev Only owner
    function pause() external;

    /// @notice Unpause protocol operations
    /// @dev Only owner
    function unpause() external;
}
