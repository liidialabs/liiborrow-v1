// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Types.sol";

/**
 * @title IDebtManager
 * @dev Interface for the DebtManager contract exposing deposit, borrow, repay,
 *      liquidation, admin configuration and view functions. Includes events
 *      emitted by the implementation.
 */
interface IDebtManager {
    // Events
    /**
     * @notice Emitted when a user deposits collateral into the protocol.
     * @param user The account that deposited collateral.
     * @param token The collateral token address (or ETH sentinel address).
     * @param amount Amount of collateral deposited.
     */
    event Supply(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when collateral is redeemed from the protocol.
     * @param redeemFrom The account whose collateral was redeemed.
     * @param redeemTo The recipient of the redeemed collateral.
     * @param token The collateral token address.
     * @param amount The amount redeemed.
     */
    event Withdraw(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted when a user is liquidated.
     * @param by The liquidator address.
     * @param from The user being liquidated.
     * @param token The collateral token seized.
     * @param amount The repay amount (USDC) used for liquidation.
     * @param timestamp The block timestamp when liquidation occurred.
     */
    event Liquidated(
        address indexed by,
        address indexed from,
        address indexed token,
        uint256 amount,
        uint32 timestamp
    );

    /**
     * @notice Emitted when a user borrows USDC from the protocol.
     * @param user The borrower.
     * @param amount The amount borrowed in USDC.
     * @param timestamp The block timestamp when borrow occurred.
     */
    event Borrow(address indexed user, uint256 amount, uint32 timestamp);

    /**
     * @notice Emitted when a user repays USDC to the protocol.
     * @param user The repayer.
     * @param amount The amount repaid in USDC.
     * @param timestamp The block timestamp when repayment occurred.
     */
    event RepayUsdc(address indexed user, uint256 amount, uint32 timestamp);

    /**
     * @notice Emitted when protocol revenue is withdrawn.
     * @param to The recipient (e.g., treasury).
     * @param asset The asset withdrawn.
     * @param amount The amount withdrawn.
     * @param timestamp The block timestamp when withdrawal occurred.
     */
    event RevenueWithdrawn(
        address indexed to,
        address indexed asset,
        uint256 amount,
        uint32 timestamp
    );

    // State-changing external functions

    /**
     * @notice Deposit an ERC20 token as collateral and supply it to Aave on behalf of the protocol.
     * @dev Caller must approve `tokenCollateralAddress` prior to calling.
     * @param tokenCollateralAddress ERC20 token address to deposit.
     * @param amountCollateral Amount of token to deposit.
     */
    function depositCollateralERC20(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external;

    /**
     * @notice Deposit ETH as collateral. ETH is wrapped into WETH and supplied to Aave.
     * @dev Call must include `msg.value == amountCollateral`.
     * @param amountCollateral Amount of ETH to deposit (in wei).
     */
    function depositCollateralETH(uint256 amountCollateral) external payable;

    /**
     * @notice Redeem collateral previously deposited by the caller.
     * @dev The call will enforce health factor and cooldown rules.
     * @param collateral The collateral token address to redeem.
     * @param amountCollateral Amount of collateral to redeem.
     * @param isEth True if redeemed asset should be returned as ETH.
     */
    function redeemCollateral(
        address collateral,
        uint256 amountCollateral,
        bool isEth
    ) external;

    /**
     * @notice Borrow USDC against supplied collateral up to the allowed borrow limit.
     * @param amountToBorrow Amount of USDC to borrow.
     */
    function borrowUsdc(uint256 amountToBorrow) external;

    /**
     * @notice Repay USDC debt (partial or full). Excess repayment is truncated.
     * @param amountToRepay Amount of USDC to repay.
     */
    function repayUsdc(uint256 amountToRepay) external;

    /**
     * @notice Set the protocol APR markup.
     * @dev Only callable by the owner; cannot set below the base APR.
     * @param _newAPR New APR markup as wad (1e18 precision).
     */
    function setProtocolAPRMarkup(uint256 _newAPR) external;

    /**
     * @notice Set the liquidation fee applied during liquidations.
     * @dev Only callable by the owner; cannot set below the base APR.
     * @param _newFee New liquidation fee as wad (1e18 precision).
     */
    function setLiquidationFee(uint256 _newFee) external;

    /**
     * @notice Set the cooldown period applied after deposits/repayments.
     * @dev Only callable by the owner; capped by a protocol maximum.
     * @param _newCoolDown New cooldown period in seconds.
     */
    function setCoolDownPeriod(uint256 _newCoolDown) external;

    /**
     * @notice Add a new collateral asset to the protocol.
     * @param collateral Address of the collateral token.
     */
    function addCollateralAsset(address collateral) external;

    /**
     * @notice Pause deposit activity for a given collateral token.
     * @param collateral Address of the collateral token to pause.
     */
    function pauseCollateralActivity(address collateral) external;

    /**
     * @notice Unpause deposit activity for a given collateral token.
     * @param collateral Address of the collateral token to unpause.
     */
    function unPauseCollateralActivity(address collateral) external;

    /**
     * @notice Pause protocol operations (only owner).
     */
    function pause() external;

    /**
     * @notice Unpause protocol operations (only owner).
     */
    function unpause() external;

    /**
     * @notice Returns the user's LTV (loan-to-value) ratio as wad (1e18).
     * @param user The address of the user.
     * @return ltv User's LTV in wad (1e18). Returns uint.max if no collateral or no debt.
     */
    function userLTV(address user) external returns (uint256 ltv);

    /**
     * @notice Check if a given user is liquidatable by protocol rules.
     * @param user The address of the user.
     * @return True if liquidatable, false otherwise.
     */
    function isLiquidatable(address user) external returns (bool);

    /**
     * @notice Liquidate an undercollateralized user by repaying part of their debt and seizing collateral.
     * @param user The address of the user to liquidate.
     * @param collateral The collateral token to seize.
     * @param repayAmount The amount of USDC to repay on the user's behalf.
     * @param isEth True if seized collateral should be returned as ETH.
     */
    function liquidate(
        address user,
        address collateral,
        uint256 repayAmount,
        bool isEth
    ) external;

    /**
     * @notice Withdraw accrued protocol revenue to a treasury address.
     * @param to The recipient address.
     * @param asset The asset to withdraw.
     * @param amount The amount to withdraw.
     */
    function withdrawRevenue(
        address to,
        address asset,
        uint256 amount
    ) external;

    // Read-only / view functions

    /**
     * @notice Convert a USD value into an amount of collateral.
     * @param collateral The collateral token address.
     * @param valueOfRepayAmount The USD value to convert (1e18 = 1 USD).
     * @return The amount of collateral corresponding to the given USD value.
     */
    function getCollateralAmount(
        address collateral,
        uint256 valueOfRepayAmount
    ) external view returns (uint256);

    /**
     * @notice Convert a USD repay value into an amount of collateral including liquidation bonus.
     * @param collateral The collateral token address.
     * @param valueOfRepayAmount The USD repay value (1e18 = 1 USD).
     * @return The amount of collateral to seize for the given repay value.
     */
    function getCollateralAmountLiquidate(
        address collateral,
        uint256 valueOfRepayAmount
    ) external view returns (uint256);

    /**
     * @notice Returns the maximum collateral amount a user can withdraw for a specific token.
     * @param user The user's address.
     * @param collateral The collateral token address.
     * @return The maximum withdrawable amount of collateral.
     */
    function getUserMaxCollateralWithdrawAmount(
        address user,
        address collateral
    ) external returns (uint256);

    /**
     * @notice Returns true if the token is supported as collateral.
     * @param token The token address to check.
     * @return True if supported, false otherwise.
     */
    function checkIfTokenSupported(address token) external view returns (bool);

    /**
     * @notice Returns true if deposits for the given collateral are paused.
     * @param token The token address to check.
     * @return True if paused, false otherwise.
     */
    function checkIfCollateralPaused(
        address token
    ) external view returns (bool);

    /**
     * @notice Returns the maximum borrowable value (USD) and amount (USDC) for a user.
     * @param user The user's address.
     * @return value Maximum borrowable value in USD (1e18 = 1 USD).
     * @return amount Maximum borrowable amount in USDC (in token decimals).
     */
    function getUserMaxBorrow(
        address user
    ) external returns (uint256 value, uint256 amount);

    /**
     * @notice Returns a user's owed amounts: debt owed to Aave and total debt including protocol cut.
     * @param user The user's address.
     * @return userAaveDebt Debt owed to Aave (USDC).
     * @return userTotalDebt Total debt including protocol cut (USDC).
     */
    function getUserDebt(
        address user
    ) external returns (uint256 userAaveDebt, uint256 userTotalDebt);

    /**
     * @notice Returns the platform's current debt values.
     * @return aaveDebt The current variable debt owed to Aave (in underlying precision).
     * @return totalDebt The protocol total debt including APR markup.
     */
    function getPlatformDebt()
        external
        returns (uint256 aaveDebt, uint256 totalDebt);

    /**
     * @notice Returns the protocol revenue accrued.
     * @return The protocol revenue accrued in USDC or token units.
     */
    function getProtocolRevenue() external view returns (uint256);

    /**
     * @notice Returns the protocol APR markup.
     * @return apr The APR markup as wad (1e18).
     */
    function getProtocolAPRMarkup() external view returns (uint256);

    /**
     * @notice Returns the liquidation fee applied by the protocol.
     * @return fee The liquidation fee as wad (1e18).
     */
    function getLiquidationFee() external view returns (uint256);

    /**
     * @notice Returns the liquidation bonus for a collateral (bonus part only).
     * @param collateral The collateral token address.
     * @return bonus The liquidation bonus (e.g., 0.05e18 for 5%).
     */
    function getLiquidationBonus(
        address collateral
    ) external view returns (uint256 bonus);

    /**
     * @notice Returns the cooldown period applied after certain actions.
     * @return period The cooldown period in seconds.
     */
    function getCoolDownPeriod() external view returns (uint256);

    /**
     * @notice Returns a user's health factor and high-level health status.
     * @param user The user's address.
     * @return healthFactor The user's health factor (wad, 1e18 = 1.0).
     * @return status The health status enum (Healthy / Danger / Liquidatable).
     */
    function getUserHealthFactor(
        address user
    ) external returns (uint256 healthFactor, HealthStatus status);

    /**
     * @notice Returns the user's total debt to repay including protocol cut in USD value (1e18 = 1 USD).
     * @param user The user's address.
     * @return totalUsdcToRepay Total debt to repay in USD value (wad).
     */
    function getUserTotalDebt(
        address user
    ) external returns (uint256 totalUsdcToRepay);

    /**
     * @notice Returns a user's account data including total collateral, total debt and health factor.
     * @param user The user's address.
     * @return _totalCollateral Total collateral value in USD (1e8 = 1 USD as per Aave feed scaling).
     * @return _totalDebt Total debt value in USD (1e8 = 1 USD as per Aave feed scaling).
     * @return _hFactor The health factor of the user.
     */
    function getUserAccountData(
        address user
    )
        external
        returns (
            uint256 _totalCollateral,
            uint256 _totalDebt,
            uint256 _hFactor
        );

    /**
     * @notice Returns the USD value of a token amount.
     * @param token The token address.
     * @param amount The token amount.
     * @return value The USD value (1e18 = 1 USD).
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256);

    /**
     * @notice Returns the on-chain price of an asset from the configured oracle.
     * @param token The token address.
     * @return price The asset price in USD (1e8 = 1 USD).
     */
    function getAssetPrice(address token) external view returns (uint256 price);

    /**
     * @notice Returns the collateral balance of a user for a specific token.
     * @param user The user's address.
     * @param token The collateral token address.
     * @return balance The collateral balance for the user.
     */
    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256);

    /**
     * @notice Returns the total collateral value of a user in USD (wad precision used internally).
     * @param user The user's address.
     * @return totalCollateralValueInUsd Total collateral value in USD (wad).
     */
    function getAccountCollateralValue(
        address user
    ) external view returns (uint256 totalCollateralValueInUsd);

    /**
     * @notice Returns the platform LLTV and LTV, based on the DebtManager's Aave position.
     * @return lltv Platform liquidation loan-to-value ratio (wad, 1e18 = 1.0).
     * @return ltv Platform loan-to-value ratio (wad, 1e18 = 1.0).
     */
    function getPlatformLltvAndLtv()
        external
        returns (uint256 lltv, uint256 ltv);

    /**
     * @notice Returns the list of collateral token addresses supported by the protocol.
     * @return tokens Array of collateral token addresses.
     */
    function getCollateralTokens() external view returns (address[] memory);

    /**
     * @notice Returns the total collateral supplied for a given token.
     * @param collateral The collateral token address.
     * @return totalColSupplied The total supplied amount for the token.
     */
    function getTotalColSupplied(
        address collateral
    ) external view returns (uint256);

    /**
     * @notice Returns the total debt shares in the protocol.
     * @return totalDebtShares The total debt shares.
     */
    function getTotalDebtShares() external view returns (uint256);

    /**
     * @notice Returns the debt share balance for a specific user.
     * @param user The user's address.
     * @return userShares The user's debt shares.
     */
    function getUserShares(address user) external view returns (uint256);

    /**
     * @notice Returns the health factor of a user (internal accounting).
     * @param user The user's address.
     * @return healthFactor The user's health factor (wad).
     */
    function getHealthFactor(address user) external returns (uint256);

    /**
     * @notice Returns the next permitted activity timestamp for a user (cooldown enforcement).
     * @param user The user's address.
     * @return timestamp The next activity timestamp as a uint32.
     */
    function getNextActivity(address user) external view returns (uint32);

    /**
     * @notice Returns an array with each collateral token symbol and amount supplied by the user.
     * @param user The user's address.
     * @return userCollateral Array of UserCollateral structs with token symbol and amount.
     */
    function getUserSuppliedCollateralAmount(
        address user
    ) external view returns (UserCollateral[] memory);

    /**
     * @notice Returns liquidation revenue accrued per collateral token.
     * @return liquidationEarnings Array of LiquidationEarnings structs with token symbol and amount.
     */
    function getLiquidationRevenue()
        external
        view
        returns (LiquidationEarnings[] memory);

    /**
     * @notice Returns liquidation revenue accrued for a specific collateral token.
     * @param asset The collateral token address.
     * @return revenue The accrued liquidation revenue for the asset.
     */
    function getLiquidationRevenueSpecific(
        address asset
    ) external view returns (uint256);
}
