// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPool} from "./interfaces/aave-v3/IPool.sol";
import {IPoolDataProvider} from "./interfaces/aave-v3/IPoolDataProvider.sol";
import {IPriceOracle} from "./interfaces/aave-v3/IPriceOracle.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import "./Types.sol";

/**
 * @title Aave
 * @author Liidia Team
 * @notice Facade contract for interacting with Aave V3 protocol.
 * @dev Provides read-only wrappers around Aave's Pool, Oracle, and DataProvider
 *      to fetch account data, prices, and liquidity information for the protocol.
 *      All view functions return normalized values for use in the DebtManager.
 */
contract Aave {
    /// @notice The Aave V3 Pool contract for supply/borrow operations.
    IPool public immutable pool;

    /// @notice The Aave V3 Oracle for fetching asset prices.
    IPriceOracle public immutable oracle;

    /// @notice The Aave V3 PoolDataProvider for reserve configuration data.
    IPoolDataProvider public immutable poolDataProvider;

    /// @notice The USDC token address used as the debt asset.
    address public immutable USDC;

    /// @notice The health status of the protocol's position (derived from Aave data).
    HealthStatus public healthStatus;

    /// @notice Precision for health factor calculations (1e18 = 1.0 HF).
    uint256 private constant HF_PRECISION = 1e18;

    /// @notice Base precision for percentage calculations (1e18 = 100%).
    uint256 private constant BASE_PRECISION = 1e18;

    /// @notice Precision for percentage-based values (1e4 = 1%).
    uint256 private constant PERCENT_PRECISION = 1e4;

    /// @notice Precision for USD prices (1e8 = 1 USD).
    uint256 private constant PRICE_PRECISION = 1e8;

    /// @notice The decimal precision of the vToken (aToken/vToken) for the debt asset.
    uint8 public vTokenDecimals;

    /// @notice Initializes the Aave contract with required protocol addresses.
    /// @param _pool The Aave Pool address.
    /// @param _oracle The Aave Oracle address.
    /// @param _dataProvider The Aave PoolDataProvider address.
    /// @param _usdc The USDC token address.
    constructor(
        address _pool,
        address _oracle,
        address _dataProvider,
        address _usdc
    ) {
        pool = IPool(_pool);
        oracle = IPriceOracle(_oracle);
        poolDataProvider = IPoolDataProvider(_dataProvider);
        USDC = _usdc;
        IPool.ReserveData memory reserve = pool.getReserveData(_usdc);
        vTokenDecimals = IERC20Metadata(reserve.variableDebtTokenAddress)
            .decimals();
    }

    /// @notice Retrieves the current variable borrow APR for USDC from Aave.
    /// @return variableBorrowAPR The current variable borrow rate in ray (1e27).
    /// @dev This rate is dynamic and changes based on Aave's liquidity and utilization.
    function getVariableBorrowAPR()
        external
        view
        returns (uint256 variableBorrowAPR)
    {
        IPool.ReserveData memory reserve = pool.getReserveData(USDC);
        return reserve.currentVariableBorrowRate;
    }

    /// @notice Fetches account data for a given custodian from Aave.
    /// @param custodian The DebtManager address acting as custodian.
    /// @return collateralUSD Total collateral value supplied in USD (1e8 = 1 USD).
    /// @return debtUSD Total debt value in USD (1e8 = 1 USD).
    /// @return canBorrowUSD Available borrow power in USD (1e8 = 1 USD).
    /// @return canBorrowUSDC Available borrow power in USDC (in USDC units).
    /// @return _currentLiquidationThreshold The liquidation threshold (unit: 10000, e.g., 8000 = 80%).
    /// @return _ltv The loan-to-value ratio (unit: 10000, e.g., 7500 = 75%).
    function getUserAccountData(
        address custodian
    )
        public
        view
        returns (
            uint256 collateralUSD,
            uint256 debtUSD,
            uint256 canBorrowUSD,
            uint256 canBorrowUSDC,
            uint256 _currentLiquidationThreshold,
            uint256 _ltv
        )
    {
        uint256 price = oracle.getAssetPrice(USDC);
        uint256 decimals = IERC20Metadata(USDC).decimals();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,

        ) = pool.getUserAccountData(custodian);

        collateralUSD = totalCollateralBase / PRICE_PRECISION;
        debtUSD = totalDebtBase / PRICE_PRECISION;
        canBorrowUSD = availableBorrowsBase / PRICE_PRECISION;
        canBorrowUSDC = (availableBorrowsBase * (10 ** decimals)) / price;

        _currentLiquidationThreshold = currentLiquidationThreshold;
        _ltv = ltv;
    }

    /// @notice Calculates the health factor and status for a custodian position.
    /// @param custodian The DebtManager address.
    /// @return hf The health factor (1e18 = 1.0). Values < 1e18 indicate undercollateralization.
    /// @return status The HealthStatus enum (Healthy/Danger/Liquidatable).
    function getHealthFactor(
        address custodian
    ) public view returns (uint256 hf, HealthStatus status) {
        (, , , , , uint256 healthFactor) = pool.getUserAccountData(custodian);

        if (healthFactor < 1e18) {
            status = HealthStatus.Liquidatable;
        } else if (healthFactor <= 1.1e18) {
            status = HealthStatus.Danger;
        } else {
            status = HealthStatus.Healthy;
        }

        hf = healthFactor;
    }

    /// @notice Validates that a borrow would not break the health factor requirement.
    /// @dev Reverts if the new health factor would be below 1.1 or if borrow exceeds available liquidity.
    /// @param amountToBorrow The amount of USDC to borrow.
    /// @param custodian The DebtManager address.
    function revertIfHFBreaks(
        uint256 amountToBorrow,
        address custodian
    ) external view {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            ,

        ) = pool.getUserAccountData(custodian);

        uint256 price = oracle.getAssetPrice(USDC);
        uint256 decimals = IERC20Metadata(USDC).decimals();

        uint256 amountInUsd = (amountToBorrow * price) / (10 ** decimals);
        if (amountInUsd > availableBorrowsBase) {
            revert ErrorsLib.Aave__ExceedsMaxBorrow();
        }

        uint256 newDebtBase = totalDebtBase + amountInUsd;
        uint256 newHealthFactor = (totalCollateralBase *
            currentLiquidationThreshold *
            HF_PRECISION) / (newDebtBase * PERCENT_PRECISION);

        if (newHealthFactor < 1.1e18) {
            revert ErrorsLib.Aave__RiskyHealthFactor();
        }
    }

    /// @notice Checks if a custodian position is at risk of liquidation.
    /// @param custodian The DebtManager address.
    /// @return True if health factor < 1.1, indicating elevated risk.
    function isAtRisk(address custodian) public view returns (bool) {
        (, , , , , uint256 hf) = pool.getUserAccountData(custodian);
        return hf < 1.1e18;
    }

    /// @notice Gets the variable debt balance for an account in a specific asset.
    /// @param custodian The account address.
    /// @param asset The asset address (e.g., USDC).
    /// @return The variable debt amount in underlying token units.
    function getVariableDebt(
        address custodian,
        address asset
    ) public view returns (uint256) {
        IPool.ReserveData memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(custodian);
    }

    /// @notice Gets the supply (aToken) balance for an account in a specific asset.
    /// @param custodian The account address.
    /// @param asset The asset address (e.g., WETH).
    /// @return The supply balance in underlying token units.
    function getSupplyBalance(
        address custodian,
        address asset
    ) public view returns (uint256) {
        IPool.ReserveData memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.aTokenAddress).balanceOf(custodian);
    }

    /// @notice Fetches the price of an asset from the Aave oracle.
    /// @param asset The asset address.
    /// @return price The asset price in USD (1e8 = 1 USD).
    /// @dev Reverts if the price is zero or invalid.
    function getAssetPrice(address asset) public view returns (uint256 price) {
        price = oracle.getAssetPrice(asset);
        if (price == 0) {
            revert ErrorsLib.Aave__InvalidPrice();
        }
    }

    /// @notice Gets the liquidation bonus for a collateral asset.
    /// @param asset The collateral asset address.
    /// @return liquidationBonus The liquidation bonus as a wad (1e18 = 100%).
    /// @dev For example, 1.05e18 means 5% bonus on top of collateral value.
    function getAssetLiquidationBonus(
        address asset
    ) public view returns (uint256 liquidationBonus) {
        (, , , uint256 _liquidationBonus, , , , , , ) =
            poolDataProvider.getReserveConfigurationData(asset);
        liquidationBonus =
            (_liquidationBonus * BASE_PRECISION) /
            PERCENT_PRECISION;
    }
}
