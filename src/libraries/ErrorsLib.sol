// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

library ErrorsLib {
    // DebtManager Errors

    error DebtManager__CollateralAssetsNotParsed();
    error DebtManager__NeedsMoreThanZero();
    error DebtManager__ZeroAddress();
    error DebtManager__TokenNotAllowed(address token);
    error DebtManager__TokenNotSupported(address token);
    error DebtManager__TransferFailed();
    error DebtManager__BreaksHealthFactor();
    error DebtManager__MintFailed();
    error DebtManager__HealthFactorOk();
    error DebtManager__HealthFactorNotImproved();
    error DebtManager__AmountNotEqual();
    error DebtManager__CoolDownActive();
    error DebtManager__NoCollateralSupplied();
    error DebtManager__NoAssetBorrowed();
    error DebtManager__UserNotLiquidatable();
    error DebtManager__UserHasNoCollateral();
    error DebtManager__InsufficientCollateral();
    error DebtManager__BelowBaseApr();
    error DebtManager__AlreadyAtBreakingPoint();
    error DebtManager__ExceedsMaxCoolDown();
    error DebtManager__CollateralAlreadyPaused(address token);
    error DebtManager__CollateralActivityPaused(address token);
    error DebtManager__CollateralNotPaused(address token);
    error DebtManager__InsufficientAmountToWithdraw();

    // Aave Errors
    error Aave__ExceedsMaxBorrow();
    error Aave__RiskyHealthFactor();
    error Aave__ZeroPrice();
    error Aave__InvalidPrice();
}
