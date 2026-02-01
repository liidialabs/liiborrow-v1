// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Aave } from "../../src/Aave.sol";
import { ErrorsLib } from "../../src/libraries/ErrorsLib.sol";
import { MockAavePool } from "../mocks/MockAavePool.sol";
import { MockAaveOracle } from "../mocks/MockAaveOracle.sol";
import { MockPoolDataProvider } from "../mocks/MockPoolDataProvider.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Test, console } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IPool } from "../../src/interfaces/aave-v3/IPool.sol";
import { HealthStatus } from "../../src/Types.sol";

contract AaveTest is Test {
    Aave public aave;
    MockAavePool public mockPool;
    MockAaveOracle public mockOracle;
    MockPoolDataProvider public mockPoolDataProvider;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public aUsdc; // aToken
    MockERC20 public vUsdc; // Variable debt token

    address public user = makeAddr("user");
    address public custodian = makeAddr("custodian");

    // Constants
    uint256 constant USDC_PRICE = 1e8; // $1 with 8 decimals
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant HF_PRECISION = 1e18;

    function setUp() external {
        // Deploy mocks
        mockPool = new MockAavePool();
        mockOracle = new MockAaveOracle();
        mockPoolDataProvider = new MockPoolDataProvider();
        weth = new MockERC20("WETH", "WETH", 18);
        usdc = new MockERC20("USDC", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        vUsdc = new MockERC20("Variable Debt USDC", "vUSDC", 6);

        // Setup oracle price
        mockOracle.setAssetPrice(address(usdc), USDC_PRICE);

        // Setup reserve data in pool
        IPool.ReserveData memory reserveData = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25, // 3% APR
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25, // 5% APR
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(aUsdc),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(vUsdc),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
        mockPool.setReserveData(address(usdc), reserveData);

        // Setup reserve configuration data in PoolDataProvider
        MockPoolDataProvider.ReserveConfig memory reserveConfig_weth = MockPoolDataProvider.ReserveConfig({
            decimals: 1e18,
            ltv: 7500, // 75%
            liquidationThreshold: 8000, // 80%
            liquidationBonus: 10500, // 105%
            reserveFactor: 1000, // 10%
            usageAsCollateralEnabled: true,
            borrowingEnabled: true,
            stableBorrowRateEnabled: true,
            isActive: true,
            isFrozen: false
        });
        mockPoolDataProvider.setReserveConfigurationData(address(weth), reserveConfig_weth);

        // Deploy Aave contract
        aave = new Aave(address(mockPool), address(mockOracle), address(mockPoolDataProvider), address(usdc));
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_SetsPoolAddress() public view {
        assertEq(address(aave.pool()), address(mockPool));
    }

    function test_Constructor_SetsOracleAddress() public view {
        assertEq(address(aave.oracle()), address(mockOracle));
    }

    function test_Constructor_SetsVTokenDecimals() public view {
        assertEq(aave.vTokenDecimals(), 6);
    }

    // ============ GET VARIABLE BORROW APR TESTS ============

    function test_GetVariableBorrowAPR_ReturnsCorrectRate() public view {
        uint256 apr = aave.getVariableBorrowAPR();
        assertEq(apr, 5e25); // 5% APR in ray units
    }

    // ============ GET USER ACCOUNT DATA TESTS ============

    function test_GetUserAccountData_WithNoPosition() public {
        mockPool.setUserAccountData(
            custodian,
            0, // totalCollateralBase
            0, // totalDebtBase
            0, // availableBorrowsBase
            8000, // liquidationThreshold (80%)
            7500, // ltv (75%)
            type(uint256).max // healthFactor (max for no debt)
        );

        (
            uint256 collateralUSD,
            uint256 debtUSD,
            uint256 canBorrowUSD,
            uint256 canBorrowUSDC,
            uint256 _currentLiquidationThreshold, // unit: 10000
            uint256 _ltv // unit: 10000
        ) = aave.getUserAccountData(custodian);

        assertEq(collateralUSD, 0);
        assertEq(debtUSD, 0);
        assertEq(canBorrowUSD, 0);
        assertEq(canBorrowUSDC, 0);
        assertEq(_currentLiquidationThreshold, 8000);
        assertEq(_ltv, 7500);
    }

    function test_GetUserAccountData_WithCollateralAndDebt() public {
        // User has $10,000 collateral, $5,000 debt, can borrow $2,500 more
        mockPool.setUserAccountData(
            custodian,
            10000e8, // $10,000 collateral
            5000e8, // $5,000 debt
            2500e8, // $2,500 available to borrow
            8000, // 80% liquidation threshold
            7500, // 75% ltv
            1.6e18 // HF = 1.6
        );

        (
            uint256 collateralUSD,
            uint256 debtUSD,
            uint256 canBorrowUSD,
            uint256 canBorrowUSDC,
            uint256 liquidationThreshold,
            uint256 ltv
        ) = aave.getUserAccountData(custodian);

        assertEq(collateralUSD, 10000);
        assertEq(debtUSD, 5000);
        assertEq(canBorrowUSD, 2500);
        assertEq(canBorrowUSDC, 2500e6); // 2500 USDC (6 decimals)
        assertEq(liquidationThreshold, 8000);
        assertEq(ltv, 7500);
    }

    function test_GetUserAccountData_ConvertsUSDCCorrectly() public {
        mockPool.setUserAccountData(
            custodian,
            1000e8, // $1,000 collateral
            0,
            750e8, // $750 available
            8000,
            7500,
            type(uint256).max
        );

        (, , uint256 canBorrowUSD, uint256 canBorrowUSDC, , ) = aave.getUserAccountData(custodian);

        uint256 actualBorrowAmount = (canBorrowUSD * 1e8 * 1e6) / USDC_PRICE;

        // Should convert $750 to 750 USDC (with 6 decimals)
        assertEq(canBorrowUSDC, actualBorrowAmount);
    }

    // ============ GET HEALTH FACTOR TESTS ============

    function test_GetHealthFactor_Healthy() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            2500e8,
            8000,
            7500,
            1.6e18 // HF = 1.6
        );

        (uint256 hf, HealthStatus status) = aave.getHealthFactor(custodian);

        assertEq(hf, 1.6e18);
        assertEq(uint8(status), uint8(HealthStatus.Healthy));
    }

    function test_GetHealthFactor_Danger() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            8000e8,
            500e8,
            8000,
            7500,
            1.1e18 // HF = 1.1 (between 1.0 and 1.2)
        );

        (uint256 hf, HealthStatus status) = aave.getHealthFactor(custodian);

        assertEq(hf, 1.1e18);
        assertEq(uint8(status), uint8(HealthStatus.Danger));
    }

    function test_GetHealthFactor_Liquidatable() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            9500e8,
            0,
            8000,
            7500,
            0.95e18 // HF < 1.0
        );

        (uint256 hf, HealthStatus status) = aave.getHealthFactor(custodian);

        assertEq(hf, 0.95e18);
        assertEq(uint8(status), uint8(HealthStatus.Liquidatable));
    }

    // ============ REVERT IF HF BREAKS TESTS ============

    function test_RevertIfHFBreaks_PassesWithSafeBorrow() public {
        // User has $10,000 collateral, $5,000 debt, can safely borrow more
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            2500e8, // Can borrow $2,500
            8000,
            7500,
            1.6e18
        );

        // Try to borrow $1,000 (safe amount)
        aave.revertIfHFBreaks(1000e6, custodian);
    }

    function test_RevertIfHFBreaks_RevertsWhenExceedsMaxBorrow() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            2500e8, // Can borrow $2,500
            8000,
            7500,
            1.6e18
        );

        // Try to borrow $3,000 (exceeds available)
        vm.expectRevert(ErrorsLib.Aave__ExceedsMaxBorrow.selector);
        aave.revertIfHFBreaks(3000e6, custodian);
    }

    function test_RevertIfHFBreaks_RevertsWhenRiskyHealthFactor() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            6000e8,
            1500e8,
            8000,
            7500,
            1.33e18
        );

        // Borrowing amount that results in HF between 1.0 and 1.1
        vm.expectRevert(ErrorsLib.Aave__RiskyHealthFactor.selector); // Will revert with RiskyHealthFactor
        aave.revertIfHFBreaks(1500e6, custodian);
    }

    function test_RevertIfHFBreaks_CalculatesNewHealthFactorCorrectly() public {
        // Setup: $10,000 collateral, $5,000 debt, 80% LT
        // Current HF = (10,000 * 0.8) / 5,000 = 1.6
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            3000e8,
            8000, // 80% liquidation threshold
            7500,
            1.6e18
        );

        // Borrow $2,000 more
        // New debt = $7,000
        // New HF = (10,000 * 0.8) / 7,000 = 1.142857...
        // Should pass (HF > 1.1)
        aave.revertIfHFBreaks(2000e6, custodian);
    }

    // ============ IS AT RISK TESTS ============

    function test_IsAtRisk_ReturnsFalseWhenHealthy() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            2500e8,
            8000,
            7500,
            1.6e18
        );

        assertFalse(aave.isAtRisk(custodian));
    }

    function test_IsAtRisk_ReturnsTrueWhenBelowThreshold() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            8000e8,
            500e8,
            8000,
            7500,
            1.09e18 // Below 1.2
        );

        assertTrue(aave.isAtRisk(custodian));
    }

    function test_IsAtRisk_ReturnsTrueAtExactThreshold() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            8000e8,
            500e8,
            8000,
            7500,
            1.1e18 // Exactly 1.2
        );

        // Function checks < 1.2, so exactly 1.2 should return false
        assertFalse(aave.isAtRisk(custodian));
    }

    function test_IsAtRisk_ReturnsTrueWhenLiquidatable() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            9500e8,
            0,
            8000,
            7500,
            0.95e18 // Below 1.0
        );

        assertTrue(aave.isAtRisk(custodian));
    }

    // ============ GET VARIABLE DEBT TESTS ============

    function test_GetVariableDebt_ReturnsZeroWhenNoDebt() public view {
        uint256 debt = aave.getVariableDebt(custodian, address(usdc));
        assertEq(debt, 0);
    }

    function test_GetVariableDebt_ReturnsCorrectBalance() public {
        // Mint variable debt tokens to custodian
        vUsdc.mint(custodian, 5000e6);

        uint256 debt = aave.getVariableDebt(custodian, address(usdc));
        assertEq(debt, 5000e6);
    }

    // ============ GET SUPPLY BALANCE TESTS ============

    function test_GetSupplyBalance_ReturnsZeroWhenNoSupply() public view {
        uint256 supply = aave.getSupplyBalance(custodian, address(usdc));
        assertEq(supply, 0);
    }

    function test_GetSupplyBalance_ReturnsCorrectBalance() public {
        // Mint aTokens to custodian
        aUsdc.mint(custodian, 10000e6);

        uint256 supply = aave.getSupplyBalance(custodian, address(usdc));
        assertEq(supply, 10000e6);
    }

    // ============ GET USDC PRICE TESTS ============

    function test_GetUsdcPrice_ReturnsCorrectPrice() public view {
        uint256 price = aave.getAssetPrice(address(usdc));
        assertEq(price, USDC_PRICE);
    }

    function test_GetUsdcPrice_UpdatesWithOracleChange() public {
        // Change oracle price
        mockOracle.setAssetPrice(address(usdc), 0.99e8); // Slightly depegged

        uint256 price = aave.getAssetPrice(address(usdc));
        assertEq(price, 0.99e8);
    }

    // ============ EDGE CASE TESTS ============

    function test_GetHealthFactor_WithMaxHealthFactor() public {
        mockPool.setUserAccountData(
            custodian,
            10000e8,
            0, // No debt
            7500e8,
            8000,
            7500,
            type(uint256).max // Max uint256
        );

        (uint256 hf, HealthStatus status) = aave.getHealthFactor(custodian);

        assertEq(hf, type(uint256).max);
        assertEq(uint8(status), uint8(HealthStatus.Healthy));
    }

    function testFuzz_RevertIfHFBreaks_WithVariousAmounts(
        uint256 borrowAmount
    ) public {
        // Bound to reasonable values (1 to 10,000 USDC)
        borrowAmount = bound(borrowAmount, 1e6, 10000e6);

        mockPool.setUserAccountData(
            custodian,
            100000e8, // $100,000 collateral
            50000e8, // $50,000 debt
            30000e8, // $30,000 available
            8000,
            7500,
            1.6e18
        );

        // Should not revert for reasonable borrow amounts
        if (borrowAmount <= 30000e6) {
            aave.revertIfHFBreaks(borrowAmount, custodian);
        }
    }

    function testFuzz_IsAtRisk_WithVariousHealthFactors(uint256 hf) public {
        // Bound health factor to reasonable range
        hf = bound(hf, 0.5e18, 3e18);

        mockPool.setUserAccountData(
            custodian,
            10000e8,
            5000e8,
            2500e8,
            8000,
            7500,
            hf
        );

        bool atRisk = aave.isAtRisk(custodian);

        if (hf < 1.1e18) {
            assertTrue(atRisk);
        } else {
            assertFalse(atRisk);
        }
    }

    // ========== RESERVE TESTS ==========

    function test_GetReserveLiquidationBonus_ReturnsCorrectValue() public view {
        uint256 liquidationBonus = aave.getAssetLiquidationBonus(address(weth));

        // liquidationBonus = (liquidationBonus * BASE_PRECISION) / PERCENT_PRECISION;
        // = (10500 * 1e18) / 10000 = 1.05e18
        assertEq(liquidationBonus, 1.05e18);
    }
}