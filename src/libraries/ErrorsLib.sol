// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title ErrorsLib
 * @author Liidia Team
 * @notice Library containing custom error definitions for the LiiBorrow protocol.
 * @dev All errors are prefixed with the contract name for easy identification during revert.
 */
library ErrorsLib {
    // DebtManager Errors

    /// @notice Thrown when no collateral assets are provided during deployment.
    error DebtManager__CollateralAssetsNotParsed();

    /// @notice Thrown when an amount parameter is zero.
    error DebtManager__NeedsMoreThanZero();

    /// @notice Thrown when a zero address is provided where not allowed.
    error DebtManager__ZeroAddress();

    /// @notice Thrown when an operation is attempted with a disallowed token (e.g., ETH in certain contexts).
    /// @param token The token address that is not allowed.
    error DebtManager__TokenNotAllowed(address token);

    /// @notice Thrown when attempting to use a token that is not supported as collateral.
    /// @param token The token address that is not supported.
    error DebtManager__TokenNotSupported(address token);

    /// @notice Thrown when a transfer of tokens or ETH fails.
    error DebtManager__TransferFailed();

    /// @notice Thrown when an operation would break the user's health factor requirement (HF >= 1).
    error DebtManager__BreaksHealthFactor();

    /// @notice Thrown when minting of shares fails during a deposit.
    error DebtManager__MintFailed();

    /// @notice Thrown when user's health factor is acceptable (used in validation).
    error DebtManager__HealthFactorOk();

    /// @notice Thrown when a liquidation does not improve the user's health factor.
    error DebtManager__HealthFactorNotImproved();

    /// @notice Thrown when the ETH value sent does not match the specified amount.
    error DebtManager__AmountNotEqual();

    /// @notice Thrown when a user tries to perform an action before the cooldown period has elapsed.
    error DebtManager__CoolDownActive();

    /// @notice Thrown when a user has not supplied any collateral.
    error DebtManager__NoCollateralSupplied();

    /// @notice Thrown when a user has not borrowed any assets.
    error DebtManager__NoAssetBorrowed();

    /// @notice Thrown when attempting to liquidate a user who is not liquidatable.
    error DebtManager__UserNotLiquidatable();

    /// @notice Thrown when a user has no collateral to liquidate.
    error DebtManager__UserHasNoCollateral();

    /// @notice Thrown when the user does not have enough collateral for the operation.
    error DebtManager__InsufficientCollateral();

    /// @notice Thrown when trying to set an APR or fee below the base rate.
    error DebtManager__BelowBaseApr();

    /// @notice Thrown when user's position is already at the maximum borrow limit.
    error DebtManager__AlreadyAtBreakingPoint();

    /// @notice Thrown when attempting to set a cooldown period exceeding the maximum allowed.
    error DebtManager__ExceedsMaxCoolDown();

    /// @notice Thrown when attempting to pause already paused collateral.
    /// @param token The collateral token address.
    error DebtManager__CollateralAlreadyPaused(address token);

    /// @notice Thrown when attempting an operation on paused collateral.
    /// @param token The collateral token address.
    error DebtManager__CollateralActivityPaused(address token);

    /// @notice Thrown when attempting to unpause collateral that is not paused.
    /// @param token The collateral token address.
    error DebtManager__CollateralNotPaused(address token);

    /// @notice Thrown when trying to withdraw more revenue than available.
    error DebtManager__InsufficientAmountToWithdraw();

    // Aave Errors

    /// @notice Thrown when attempting to borrow more than the maximum allowed by Aave.
    error Aave__ExceedsMaxBorrow();

    /// @notice Thrown when the resulting health factor would be too risky (< 1.1).
    error Aave__RiskyHealthFactor();

    /// @notice Thrown when the oracle returns a zero price.
    error Aave__ZeroPrice();

    /// @notice Thrown when the oracle returns an invalid (zero or negative) price.
    error Aave__InvalidPrice();
}
