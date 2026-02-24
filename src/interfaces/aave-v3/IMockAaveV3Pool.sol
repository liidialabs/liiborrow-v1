// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPool.sol";

/**
 * @title IMockAaveV3Pool
 * @notice Interface for the mock Aave V3 pool used in testing.
 * @dev Extends the real `IPool` interface and exposes setters and
 *      helpers that are only available on the mock implementation.
 */
interface IMockAaveV3Pool is IPool {
    // --- setup functions ---
    function setUserAccountData(
        address user,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) external;

    function setReserveData(address asset, ReserveData memory data) external;
    function setATokenAddress(address asset, address aToken) external;
    function setUserCollateral(
        address user,
        address asset,
        uint256 amount
    ) external;
    function setUserDebt(address user, address asset, uint256 amount) external;

    // --- revert / behavior controls ---
    function setShouldRevertOnSupply(bool _shouldRevert) external;
    function setShouldRevertOnWithdraw(bool _shouldRevert) external;
    function setShouldRevertOnBorrow(bool _shouldRevert) external;
    function setShouldRevertOnRepay(bool _shouldRevert) external;
    function setShouldRevertOnLiquidation(bool _shouldRevert) external;
    function setFlashLoanFee(uint256 _fee) external;

    // --- helpers ---
    function getUserCollateral(
        address user,
        address asset
    ) external view returns (uint256);
    function getUserDebt(
        address user,
        address asset
    ) external view returns (uint256);
    function fundPool(address asset, uint256 amount) external;
}
