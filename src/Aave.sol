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

/*
 * @title Aave
 * @author Caleb Mokua
 * @description It handles fetching data from Aave
 */

contract Aave {
    // STATE

    IPool public immutable pool;
    IPriceOracle public immutable oracle;
    IPoolDataProvider public immutable poolDataProvider;
    address public immutable USDC;
    HealthStatus public healthStatus;
    uint256 private constant HF_PRECISION = 1e18;
    uint256 private constant BASE_PRECISION = 1e18;
    uint256 private constant PERCENT_PRECISION = 1e4;
    uint256 private constant PRICE_PRECISION = 1e8;
    uint8 public vTokenDecimals;

    // CONSTRUCTOR
    constructor(
        address _pool,
        address _oracle,
        address _dataProvider,
        address _usdc
    ) {
        // initialize Aave contracts
        pool = IPool(_pool);
        oracle = IPriceOracle(_oracle);
        poolDataProvider = IPoolDataProvider(_dataProvider);
        // set USDC address
        USDC = _usdc;
        // get usdc vToken decimals
        IPool.ReserveData memory reserve = pool.getReserveData(_usdc);
        vTokenDecimals = IERC20Metadata(reserve.variableDebtTokenAddress)
            .decimals();
    }

    /// @notice Get Variable borrow APR
    /// @return variableBorrowAPR The current variable borrow APR for USDC (ray - 1e27)

    function getVariableBorrowAPR()
        external
        view
        returns (uint256 variableBorrowAPR)
    {
        IPool.ReserveData memory reserve = pool.getReserveData(USDC);
        return reserve.currentVariableBorrowRate; // ray (1e27)
    }

    /// @notice Check max borrow for USDC
    /// @param custodian The address DebtManager
    /// @return collateralUSD Total collateral value supplied in USD
    /// @return debtUSD Total debt value in USD
    /// @return canBorrowUSD Amount of USD that can be borrowed
    /// @return canBorrowUSDC Amount of USDC that can be borrowed
    /// @return _currentLiquidationThreshold Current liquidation threshold (unit: 10000)
    /// @return _ltv Loan to value ratio (unit: 10000)

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
            uint256 _currentLiquidationThreshold, // unit: 10000
            uint256 _ltv // unit: 10000
        )
    {
        // 1e8 = 1 USD
        uint256 price = oracle.getAssetPrice(USDC);
        uint256 decimals = IERC20Metadata(USDC).decimals();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,

        ) = // HF
            pool.getUserAccountData(custodian);

        // Convert to USD (8 decimals)
        collateralUSD = totalCollateralBase / PRICE_PRECISION;
        debtUSD = totalDebtBase / PRICE_PRECISION;
        canBorrowUSD = availableBorrowsBase / PRICE_PRECISION;
        canBorrowUSDC = (availableBorrowsBase * (10 ** decimals)) / price;

        _currentLiquidationThreshold = currentLiquidationThreshold;
        _ltv = ltv;
    }

    /// @notice Get account HF & status
    /// @param custodian The address DebtManager
    /// @return hf Health factor of user's position
    /// @return status Health status of user's position

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

    /// @notice Check if can borrow more safely
    /// @param amountToBorrow The amount of USDC to borrow
    /// @param custodian The address DebtManager

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

        // Checks
        uint256 amountInUsd = (amountToBorrow * price) / (10 ** decimals);
        if (amountInUsd > availableBorrowsBase) {
            revert ErrorsLib.Aave__ExceedsMaxBorrow();
        }

        // Simulate new debt & calculate HF
        uint256 newDebtBase = totalDebtBase + amountInUsd;
        uint256 newHealthFactor = (totalCollateralBase *
            currentLiquidationThreshold *
            HF_PRECISION) / (newDebtBase * PERCENT_PRECISION);

        if (newHealthFactor < 1.1e18) {
            revert ErrorsLib.Aave__RiskyHealthFactor();
        }
    }

    /// @notice Monitor risk level
    /// @param custodian The address of DebtManager
    /// @return bool True if at risk, false otherwise

    function isAtRisk(address custodian) public view returns (bool) {
        (, , , , , uint256 hf) = pool.getUserAccountData(custodian);
        return hf < 1.1e18; // Warn if health factor below 1.2
    }

    /// @notice Get variable debt token for an account
    /// @param custodian The address of DebtManager
    /// @param asset The address of the asset
    /// @return variable debt amount

    function getVariableDebt(
        address custodian,
        address asset
    ) public view returns (uint256) {
        IPool.ReserveData memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(custodian);
    }

    /// @notice Get supply balance
    /// @param custodian The address of DebtManager
    /// @param asset The address of the asset
    /// @return supply balance amount

    function getSupplyBalance(
        address custodian,
        address asset
    ) public view returns (uint256) {
        IPool.ReserveData memory reserve = pool.getReserveData(asset);
        return IERC20(reserve.aTokenAddress).balanceOf(custodian);
    }

    /// @notice Get an assets price in USD (1 USD = 1e8)
    /// @param asset The address of the asset
    /// @return price The asset price in USD

    function getAssetPrice(address asset) public view returns (uint256 price) {
        price = oracle.getAssetPrice(asset);
        // check price
        if (price == 0) {
            revert ErrorsLib.Aave__InvalidPrice();
        }
    }

    /// @notice Get asset liquidation bonus
    /// @param asset The address of the asset
    /// @return liquidationBonus The asset liquidation bonus, wad 1e18

    function getAssetLiquidationBonus(
        address asset
    ) public view returns (uint256 liquidationBonus) {
        (, , , uint256 _liquidationBonus, , , , , , ) = poolDataProvider
            .getReserveConfigurationData(asset);
        liquidationBonus =
            (_liquidationBonus * BASE_PRECISION) /
            PERCENT_PRECISION; // wad (1e18)
    }
}
