// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DebtManager} from "../../src/DebtManager.sol";
import {Aave} from "../../src/Aave.sol";
import {MockAavePool} from "../mocks/MockAavePool.sol";
import {MockAaveOracle} from "../mocks/MockAaveOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {MockPoolDataProvider} from "../mocks/MockPoolDataProvider.sol";
import {IPool} from "../../src/interfaces/aave-v3/IPool.sol";
import {IDebtManager} from "../../src/interfaces/IDebtManager.sol";
import {HealthStatus, UserCollateral, LiquidationEarnings} from "../../src/Types.sol";
import { ErrorsLib } from "../../src/libraries/ErrorsLib.sol";
import { EventsLib } from "../../src/libraries/EventsLib.sol";

/**
 * @title DebtManagerFuzzTest
 * @notice Comprehensive fuzz testing for DebtManager contract
 * @dev Tests edge cases, invariants, and property-based testing
 */
contract DebtManagerFuzzTest is Test {
    DebtManager public debtManager;
    Aave public aave;
    MockAavePool public mockPool;
    MockAaveOracle public mockOracle;
    MockPoolDataProvider public mockDataProvider;
    MockERC20 public usdc;
    MockERC20 public vUsdc;
    MockERC20 public wbtc;
    MockERC20 public aWbtc;
    MockWETH public weth;
    MockERC20 public aWeth;

    // Addresses
    address public owner;
    address public user;

    // Constants matching contract
    uint256 constant MIN_HEALTH_FACTOR = 1e18;
    uint256 constant BASE_PRECISION = 1e18;
    uint256 constant COOLDOWN = 10 minutes;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // Price bounds
    int256 constant MIN_PRICE = 1e6; // $0.01
    int256 constant MAX_PRICE = 1000000e8; // $1M
    int256 constant USDC_PRICE = 1e8;
    int256 constant WETH_PRICE = 2000e8;
    int256 constant WBTC_PRICE = 40000e8;

    // Amount bounds
    uint256 constant MIN_COLLATERAL = 0.01 ether;
    uint256 constant MAX_COLLATERAL = 10 ether;
    uint256 constant MIN_BORROW = 1e6; // $1
    uint256 constant MAX_BORROW = 10000e6; // $10M

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Deploy mocks
        mockPool = new MockAavePool();
        mockOracle = new MockAaveOracle();
        mockDataProvider = new MockPoolDataProvider();
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        aWbtc = new MockERC20("Aave WBTC", "aWbtc", 8);
        weth = new MockWETH();
        aWeth = new MockERC20("Aave WETH", "aWETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vUsdc = new MockERC20("Variable Debt USDC", "vUSDC", 6);

        // Setup oracle prices
        mockOracle.setAssetPrice(address(usdc), uint256(USDC_PRICE));
        mockOracle.setAssetPrice(address(weth), uint256(WETH_PRICE));
        mockOracle.setAssetPrice(address(wbtc), uint256(WBTC_PRICE));

        // Setup reserve data
        IPool.ReserveData memory reserveData_usdc = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(vUsdc),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(vUsdc),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        IPool.ReserveData memory reserveData_weth = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(aWeth),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(aWeth),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        IPool.ReserveData memory reserveData_wbtc = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(aWbtc),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(aWbtc),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        mockPool.setReserveData(address(usdc), reserveData_usdc);
        mockPool.setReserveData(address(weth), reserveData_weth);
        mockPool.setReserveData(address(wbtc), reserveData_wbtc);

        // Setup reserve configurations
        MockPoolDataProvider.ReserveConfig memory reserveConfig_usdc = MockPoolDataProvider.ReserveConfig({
            decimals: 6,
            ltv: 7500, // 75%
            liquidationThreshold: 8000, // 80%
            liquidationBonus: 10500, // 105%
            reserveFactor: 1000, // 10%
            usageAsCollateralEnabled: true,
            borrowingEnabled: true,
            stableBorrowRateEnabled: false,
            isActive: true,
            isFrozen: false
        });
        mockDataProvider.setReserveConfigurationData(address(usdc), reserveConfig_usdc);

        // Deploy Aave
        aave = new Aave(address(mockPool), address(mockOracle), address(mockDataProvider), address(usdc));

        // Setup token arrays for DebtManager
        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = address(weth);
        tokenAddresses[1] = address(wbtc);
        tokenAddresses[2] = address(usdc);

        // Deploy DebtManager
        debtManager = new DebtManager(
            tokenAddresses,
            address(aave),
            address(usdc),
            address(weth)
        );

        // Fund pool and user
        usdc.mint(address(mockPool), 1000000e6);
        weth.mint(address(mockPool), 1000 ether);
        wbtc.mint(address(mockPool), 100e8);
        aWeth.mint(address(mockPool), 1000 ether);
        aWbtc.mint(address(mockPool), 1000e8);
        vUsdc.mint(address(mockPool), 1000000e6);
        
        weth.mint(user, 1000000 ether);
        wbtc.mint(user, 1000000e8);
        usdc.mint(user, 1000000e6);
        vm.deal(user, 100000 ether);
    }

    // ============ INVARIANT: COLLATERAL BALANCE TESTS ============

    /// @notice Collateral balance should never exceed total supplied
    function testFuzz_CollateralBalanceNeverExceedsTotalSupplied(
        uint256 depositAmount
    ) public {
        depositAmount = bound(depositAmount, MIN_COLLATERAL, MAX_COLLATERAL);

        vm.startPrank(user);
        weth.approve(address(debtManager), depositAmount);
        debtManager.depositCollateralERC20(address(weth), depositAmount);
        vm.stopPrank();

        uint256 userBalance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        uint256 totalSupplied = debtManager.getTotalColSupplied(address(weth));

        assertLe(userBalance, totalSupplied, "User balance exceeds total supplied");
    }

    /// @notice Total collateral should equal sum of all user balances
    function testFuzz_TotalCollateralEqualsUserBalances(
        uint256 user1Amount,
        uint256 user2Amount
    ) public {
        user1Amount = bound(user1Amount, MIN_COLLATERAL, MAX_COLLATERAL / 2);
        user2Amount = bound(user2Amount, MIN_COLLATERAL, MAX_COLLATERAL * 2);

        address user2 = makeAddr("user2");
        weth.mint(user2, user2Amount);

        // User 1 deposits
        vm.startPrank(user);
        weth.approve(address(debtManager), user1Amount);
        debtManager.depositCollateralERC20(address(weth), user1Amount);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        weth.approve(address(debtManager), user2Amount);
        debtManager.depositCollateralERC20(address(weth), user2Amount);
        vm.stopPrank();

        uint256 user1Balance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        uint256 user2Balance = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        uint256 totalSupplied = debtManager.getTotalColSupplied(address(weth));

        assertEq(user1Balance + user2Balance, totalSupplied, "Sum mismatch");
    }

    // ============ INVARIANT: BORROW LIMIT TESTS ============

    /// @notice User can never borrow more than liquidation threshold allows
    function testFuzz_CannotBorrowAboveLTV(
        uint256 collateralAmount,
        uint256 borrowAmount
    ) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);
        
        // Deposit collateral
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        // Setup Aave state
        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            (collateralValue * 0.75e18) / (1e8 * 1e18),
            8000,
            7500,
            type(uint256).max
        );

        // Calculate max borrow based on collateral value
        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrowValue = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 maxBorrowUSDC = maxBorrowValue / 1e8; // Convert to USDC amount

        borrowAmount = bound(borrowAmount, MIN_BORROW, maxBorrowUSDC);

        // Attempt borrow
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        // Check LTV is within threshold
        uint256 ltv = debtManager.userLTV(user);
        assertLe(ltv, _ltv, "LTV exceeds Max LTV");
    }

    /// @notice Health factor should never drop below minimum after any operation
    function testFuzz_HealthFactorMaintainedAfterBorrow(
        uint256 collateralAmount,
        uint256 borrowPercent
    ) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);

        // Deposit
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        // Setup Aave state
        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            (collateralValue * 0.75e18) / (1e8 * 1e18),
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        borrowPercent = bound(borrowPercent, 1, _ltv); // Borrow up to 60% to stay safe

        uint256 maxBorrowValue = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowValue = (maxBorrowValue * borrowPercent) / 100;
        uint256 borrowAmount = borrowValue / 1e8;

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        (uint256 hf, ) = debtManager.getUserHealthFactor(user);
        assertGe(hf, MIN_HEALTH_FACTOR, "Health factor below minimum");
    }

    // ============ INVARIANT: DEBT SHARE TESTS ============

    /// @notice Total debt shares should equal sum of all user shares
    function testFuzz_TotalDebtSharesEqualsUserShares(
        uint256 user1Borrow,
        uint256 user2Borrow
    ) public {
        user1Borrow = bound(user1Borrow, 10e6, 10000e6);
        user2Borrow = bound(user2Borrow, 10e6, 10000e6);

        address user2 = makeAddr("user2");
        weth.mint(user2, 100 ether);

        // Setup both users with collateral
        uint256 collateral1 = 10 ether;
        uint256 collateral2 = 10 ether;

        vm.startPrank(user);
        weth.approve(address(debtManager), collateral1);
        debtManager.depositCollateralERC20(address(weth), collateral1);
        vm.stopPrank();

        vm.startPrank(user2);
        weth.approve(address(debtManager), collateral2);
        debtManager.depositCollateralERC20(address(weth), collateral2);
        vm.stopPrank();

        uint256 collateralValue = 20000e8;
        _setUserAccountData(
            address(debtManager),
            collateralValue,
            0,
            15000e8,
            8000,
            7500,
            type(uint256).max
        );

        // Both users borrow
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(user1Borrow);

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(user2Borrow);

        // Shares
        uint256 user1Shares = debtManager.getUserShares(user);
        uint256 user2Shares = debtManager.getUserShares(user2);
        uint256 totalShares = debtManager.getTotalDebtShares();
        assertEq(user1Shares + user2Shares, totalShares, "Total shares should be equal");

        // Debt
        (uint256 user1AaveDebt,uint256 user1TotalDebt) = debtManager.getUserDebt(user);
        (uint256 user2AaveDebt,uint256 user2TotalDebt) = debtManager.getUserDebt(user2);
        (uint256 platformAaveDebt, uint256 totalDebt) = debtManager.getPlatformDebt();

        // Allow 1 wei per user of rounding difference (2 wei total max)
        uint256 totalUsersAaveDebt = user1AaveDebt + user2AaveDebt;
        uint256 aaveDifference = totalUsersAaveDebt > platformAaveDebt 
            ? totalUsersAaveDebt - platformAaveDebt 
            : platformAaveDebt - totalUsersAaveDebt;
        assertLe(aaveDifference, 2, "Aave debt accounting error exceeds rounding tolerance");

        // Allow 1 wei per user of rounding difference (2 wei total max)
        uint256 totalUsersDebt = user1TotalDebt + user2TotalDebt;
        uint256 difference = totalUsersDebt > totalDebt 
            ? totalUsersDebt - totalDebt 
            : totalDebt - totalUsersDebt;
        assertLe(difference, 2, "Debt accounting error exceeds rounding tolerance");

        assertLt(totalUsersAaveDebt, totalUsersDebt, "Aave debt should be less than total debt");
    }

    /// @notice Repaying debt should reduce shares proportionally
    function testFuzz_RepayReducesSharesProportionally(
        uint256 borrowAmount,
        uint256 repayPercent
    ) public {
        borrowAmount = bound(borrowAmount, 1000e6, 10000e6);
        repayPercent = bound(repayPercent, 1, 100);

        // Setup and borrow
        uint256 collateral = 20 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            40000e8,
            0,
            24000e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        (,uint256 debtBefore) = debtManager.getUserDebt(user);
        uint256 sharesBefore = debtManager.getTotalDebtShares();

        // Repay portion
        uint256 repayAmount = (borrowAmount * repayPercent) / 100;
        if (repayAmount == 0) repayAmount = 1e6;

        vm.startPrank(user);
        usdc.approve(address(debtManager), repayAmount);
        debtManager.repayUsdc(repayAmount);
        vm.stopPrank();

        (,uint256 debtAfter) = debtManager.getUserDebt(user);
        uint256 sharesAfter = debtManager.getTotalDebtShares();

        assertLt(debtAfter, debtBefore, "Debt should decrease");
        assertLt(sharesAfter, sharesBefore, "Shares should decrease");
    }

    // ============ INVARIANT: LIQUIDATION TESTS ============

    /// @notice Liquidation should only succeed when LTV >= liquidation threshold
    function testFuzz_LiquidationOnlyWhenAboveThreshold(uint256 priceDrop) public {
        priceDrop = bound(priceDrop, 1, 90); // 1-90% price drop

        // Setup user position
        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            20000e8,
            0,
            13000e8,
            8000,
            7500,
            type(uint256).max
        );

        (uint256 _lltv,) = debtManager.getPlatformLltvAndLtv();

        // Borrow near limit
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(12000e6);

        // Drop price
        int256 newPrice = (WETH_PRICE * int256(priceDrop)) / 100;
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        bool isLiquidatable = debtManager.isLiquidatable(user);
        uint256 ltv = debtManager.userLTV(user);

        if (isLiquidatable) {
            assertGe(ltv, _lltv, "Should only be liquidatable above threshold");
        } else {
            assertLt(ltv, _lltv, "Should not be liquidatable below threshold");
        }
    }

    /// @notice Liquidation should improve or maintain protocol health
    function testFuzz_LiquidationImprovesHealth(
        uint256 collateralAmount,
        uint256 repayPercent,
        uint256 priceDrop
    ) public {
        collateralAmount = bound(collateralAmount, 5 ether, 50 ether);
        repayPercent = bound(repayPercent, 10, 100);
        priceDrop = bound(priceDrop, 85, 95); // 85-95% price drop

        address liquidator = makeAddr("liquidator");
        usdc.mint(liquidator, 1000000e6);

        // Setup liquidatable position
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;
        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            (collateralValue * 65) / 100 / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        uint256 borrowAmount = ((collateralValue * 65e2) / 100e2) / 1e8;

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        // Price crash to make liquidatable
        int256 newPrice = (WETH_PRICE * int256(priceDrop)) / 100;
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        if (!debtManager.isLiquidatable(user)) {
            return; // Skip if not liquidatable
        }

        (uint256 userAaveDebt,) = debtManager.getUserDebt(user);
        uint256 repayAmount = (userAaveDebt * repayPercent) / 100;
        if (repayAmount == 0) return;

        uint256 hfBefore = debtManager.getHealthFactor(user);

        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), repayAmount);
        
        try debtManager.liquidate(user, address(usdc), address(weth), repayAmount, false) {
            uint256 hfAfter = debtManager.getHealthFactor(user);
            assertGt(hfAfter, hfBefore, "Liquidation should improve HF above 1");
            assertGe(hfAfter, MIN_HEALTH_FACTOR, "HF should be improved to 1 or above");
        } catch {
            // Liquidation failed (e.g., insufficient collateral)
        }
        vm.stopPrank();
    }

    // ============ INVARIANT: WITHDRAWAL TESTS ============

    /// @notice Cannot withdraw more collateral than deposited
    function testFuzz_CannotWithdrawMoreThanDeposited(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, MIN_COLLATERAL, MAX_COLLATERAL);
        withdrawAmount = bound(withdrawAmount, 10, MAX_COLLATERAL * 2);

        vm.startPrank(user);
        weth.approve(address(debtManager), depositAmount);
        debtManager.depositCollateralERC20(address(weth), depositAmount);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            2000000e8,
            0,
            1500000e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + COOLDOWN + 1);

        uint256 balanceBefore = debtManager.getCollateralBalanceOfUser(user, address(weth));

        vm.prank(user);
        if (withdrawAmount > depositAmount) {
            // Should cap at max or revert
            try debtManager.redeemCollateral(address(weth), withdrawAmount, false) {
                uint256 balanceAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
                assertGt(balanceBefore, balanceAfter, "Balance should decrease");
            } catch {
                // Expected to revert for excessive withdrawal
            }
        } else {
            debtManager.redeemCollateral(address(weth), withdrawAmount, false);
            uint256 balanceAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
            assertEq(balanceAfter, depositAmount - withdrawAmount, "Incorrect balance");
        }
    }

    /// @notice Withdrawal should maintain health factor above minimum
    function testFuzz_WithdrawalMaintainsHealthFactor(
        uint256 collateralAmount,
        uint256 borrowPercent,
        uint256 withdrawPercent
    ) public {
        collateralAmount = bound(collateralAmount, 10 ether, 100 ether);
        borrowPercent = bound(borrowPercent, 1, 50); // Conservative borrow
        withdrawPercent = bound(withdrawPercent, 1, borrowPercent); // Partial withdrawal

        // Deposit
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 0.75e18) / BASE_PRECISION) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowAmount = (maxBorrow * borrowPercent) / (100 * 1e8);

        // Borrow
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        // Try to withdraw
        uint256 withdrawAmount = (collateralAmount * withdrawPercent) / 100;
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        try debtManager.redeemCollateral(address(weth), withdrawAmount, false) {
            (uint256 hf, ) = debtManager.getUserHealthFactor(user);
            assertGe(hf, MIN_HEALTH_FACTOR, "Health factor below minimum after withdrawal");
        } catch {
            // Withdrawal blocked due to health factor - expected behavior
        }
    }

    // ============ PROPERTY: MATHEMATICAL INVARIANTS ============

    /// @notice LTV calculation should always be consistent
    function testFuzz_LTVCalculationConsistency(
        uint256 collateralAmount,
        uint256 debtAmount
    ) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);
        debtAmount = bound(debtAmount, 100e6, 50000e6);

        // Setup
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 0.75e18) / BASE_PRECISION) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;

        if (debtAmount * 1e12 > maxBorrow) {
            return; // Skip if debt too high
        }

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(debtAmount);

        uint256 ltv = debtManager.userLTV(user);
        uint256 totalCollateralValue = debtManager.getAccountCollateralValue(user);
        (uint256 userAaveDebt,) = debtManager.getUserDebt(user);
        uint256 debtValue = debtManager.getUsdValue(address(usdc), userAaveDebt);

        // LTV should equal debt / collateral
        uint256 expectedLTV = (debtValue * BASE_PRECISION) / totalCollateralValue;
        
        // allow 0.1% error
        assertApproxEqRel(ltv, expectedLTV, 0.001e18, "LTV calculation inconsistent");
    }

    /// @notice Collateral value should be proportional to amount and price
    function testFuzz_CollateralValueProportionality(
        uint256 amount1,
        uint256 amount2
    ) public view {
        amount1 = bound(amount1, MIN_COLLATERAL, MAX_COLLATERAL / 2);
        amount2 = bound(amount2, MIN_COLLATERAL, MAX_COLLATERAL / 2);

        vm.assume(amount1 != amount2);

        uint256 value1 = debtManager.getUsdValue(address(weth), amount1);
        uint256 value2 = debtManager.getUsdValue(address(weth), amount2);

        // Values should be proportional to amounts
        uint256 ratio1 = (value1 * 1e18) / amount1;
        uint256 ratio2 = (value2 * 1e18) / amount2;

        assertEq(ratio1, ratio2, "Value not proportional to amount");
    }

    // ============ EDGE CASE TESTS ============

    /// @notice Test with extreme price volatility
    function testFuzz_ExtremePriceVolatility(uint256 priceMultiplier) public {
        priceMultiplier = bound(priceMultiplier, 1, 1000); // 0.1x to 100x

        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        // Change price dramatically
        int256 newPrice = (WETH_PRICE * int256(priceMultiplier)) / 10;
        newPrice = int256(bound(uint256(newPrice), uint256(MIN_PRICE), uint256(MAX_PRICE)));
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        // Should still be able to query value without reverting
        uint256 value = debtManager.getAccountCollateralValue(user);
        assertGt(value, 0, "Should have collateral value");
    }

    /// @notice Test cooldown enforcement across various time intervals
    function testFuzz_CooldownEnforcement(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, COOLDOWN * 2);

        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            20000e8,
            0,
            15000e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(user);
        if (timeElapsed < COOLDOWN) {
            vm.expectRevert(ErrorsLib.DebtManager__CoolDownActive.selector);
            debtManager.redeemCollateral(address(weth), 1 ether, false);
        } else {
            // Should succeed
            debtManager.redeemCollateral(address(weth), 1 ether, false);
        }
    }

    /// @notice Test protocol revenue accumulation
    function testFuzz_ProtocolRevenueAccumulation(
        uint256 aprMarkup,
        uint256 borrowAmount
    ) public {
        aprMarkup = bound(aprMarkup, 0.005e18, 0.015e18); // 0.5% to 1.5%
        borrowAmount = bound(borrowAmount, 1000e6, 10000e6);

        debtManager.setProtocolAPRMarkup(aprMarkup);

        // Setup and borrow
        uint256 collateral = 20 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            40000e8,
            0,
            26000e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        uint256 revenueBefore = debtManager.getProtocolRevenue();

        // Repay
        vm.startPrank(user);
        usdc.approve(address(debtManager), borrowAmount);
        debtManager.repayUsdc(borrowAmount);
        vm.stopPrank();

        uint256 revenueAfter = debtManager.getProtocolRevenue();

        if (aprMarkup > 0) {
            assertGt(revenueAfter, revenueBefore, "Revenue should increase");
        }
    }

    // ============ HELPER FUNCTIONS ============

    function _setUserAccountData(
        address userAddress,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) internal {
        mockPool.setUserAccountData(
            userAddress,
            totalCollateralBase,
            totalDebtBase,
            availableBorrowsBase,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        );
    }

    // ============ STATEFUL FUZZ TESTS ============

    /// @notice Multi-step fuzz test: deposit -> borrow -> price change -> check invariants
    function testFuzz_MultiStepInvariants(
        uint256 collateral,
        uint256 borrowPercent,
        uint256 priceChange
    ) public {
        collateral = bound(collateral, 1 ether, 100 ether);
        borrowPercent = bound(borrowPercent, 10, 60);
        priceChange = bound(priceChange, 50, 150); // -50% to +50%

        // Step 1: Deposit
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        uint256 collateralValue = (collateral * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 0.75e18) / BASE_PRECISION) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        // Step 2: Borrow
        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowAmount = (maxBorrow * borrowPercent) / (100 * 1e8);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        uint256 userCollateralBefore = debtManager.getCollateralBalanceOfUser(user, address(weth));
        (uint256 userDebtBefore,) = debtManager.getUserDebt(user);

        // Step 3: Price change
        int256 newPrice = (WETH_PRICE * int256(priceChange)) / 100;
        newPrice = int256(bound(uint256(newPrice), uint256(MIN_PRICE), uint256(MAX_PRICE)));
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        // Check invariants
        uint256 userCollateralAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
        (uint256 userDebtAfter,) = debtManager.getUserDebt(user);

        // Collateral balance shouldn't change from price change alone
        assertEq(userCollateralBefore, userCollateralAfter, "Collateral changed without action");
        
        // Debt balance shouldn't change from price change alone (ignoring interest)
        assertApproxEqRel(userDebtBefore, userDebtAfter, 0.001e18, "Debt changed unexpectedly");
    }

    /// @notice Complex scenario: Multiple users, deposits, borrows, repays
    function testFuzz_MultiUserScenario(
        uint256 user1Collateral,
        uint256 user2Collateral,
        uint256 user1BorrowPercent,
        uint256 user2BorrowPercent
    ) public {
        user1Collateral = bound(user1Collateral, 5 ether, 50 ether);
        user2Collateral = bound(user2Collateral, 5 ether, 50 ether);
        user1BorrowPercent = bound(user1BorrowPercent, 10, 50);
        user2BorrowPercent = bound(user2BorrowPercent, 10, 50);

        address user2 = makeAddr("user2");
        weth.mint(user2, 1000 ether);
        usdc.mint(user2, 1000000e6);

        // User 1 deposits and borrows
        vm.startPrank(user);
        weth.approve(address(debtManager), user1Collateral);
        debtManager.depositCollateralERC20(address(weth), user1Collateral);
        vm.stopPrank();

        uint256 value1 = (user1Collateral * uint256(WETH_PRICE) * 1e10) / 1e18;
        uint256 maxBorrow1 = (value1 * 0.75e18) / BASE_PRECISION;

        _setUserAccountData(
            address(debtManager),
            value1 / 1e8,
            0,
            maxBorrow1 / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        uint256 borrow1 = (maxBorrow1 * user1BorrowPercent) / (100 * 1e8);
        debtManager.borrowUsdc(borrow1);

        // User 2 deposits and borrows
        vm.startPrank(user2);
        weth.approve(address(debtManager), user2Collateral);
        debtManager.depositCollateralERC20(address(weth), user2Collateral);
        vm.stopPrank();

        uint256 value2 = (user2Collateral * uint256(WETH_PRICE) * 1e10) / 1e18;
        uint256 totalValue = value1 + value2;
        uint256 maxBorrow2 = (value2 * 0.75e18) / BASE_PRECISION;

        _setUserAccountData(
            address(debtManager),
            totalValue / 1e8,
            0,
            (maxBorrow1 + maxBorrow2) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        uint256 borrow2 = (maxBorrow2 * user2BorrowPercent) / (100 * 1e8);
        debtManager.borrowUsdc(borrow2);

        // Check invariants
        // Debt balances
        uint256 totalCollateral = debtManager.getTotalColSupplied(address(weth));
        assertEq(totalCollateral, user1Collateral + user2Collateral, "Total collateral mismatch");

        uint256 user1Balance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        uint256 user2Balance = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        assertEq(user1Balance + user2Balance, totalCollateral, "User balances don't sum to total");

        // Debt shares
        uint256 user1Shares = debtManager.getUserShares(user);
        uint256 user2Shares = debtManager.getUserShares(user2);
        uint256 totalShares = debtManager.getTotalDebtShares();
        assertEq(user1Shares + user2Shares, totalShares, "Debt shares don't sum to total");
    }

    /// @notice Stress test: Rapid deposits and withdrawals
    function testFuzz_RapidDepositWithdraw(
        uint256[5] memory amounts,
        bool[5] memory isDeposit
    ) public {
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = bound(amounts[i], 0.1 ether, 10 ether);
        }

        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < 5; i++) {
            if (isDeposit[i]) {
                // Deposit
                vm.startPrank(user);
                weth.approve(address(debtManager), amounts[i]);
                debtManager.depositCollateralERC20(address(weth), amounts[i]);
                vm.stopPrank();
                totalDeposited += amounts[i];
            } else {
                // Withdraw
                if (totalDeposited > 0) {
                    uint256 withdrawAmount = amounts[i] > totalDeposited ? totalDeposited : amounts[i];
                    vm.warp(block.timestamp + COOLDOWN + 1);
                    vm.prank(user);
                    try debtManager.redeemCollateral(address(weth), withdrawAmount, false) {
                        totalDeposited -= withdrawAmount;
                    } catch {
                        // Withdrawal failed (cooldown or other reason)
                    }
                }
            }
        }

        // Final check
        uint256 userBalance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        assertEq(userBalance, totalDeposited, "Final balance mismatch");
    }

    /// @notice Test gas consumption stays reasonable across different scenarios
    function testFuzz_GasConsumption(uint256 collateral) public {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_COLLATERAL);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        
        uint256 gasBefore = gasleft();
        debtManager.depositCollateralERC20(address(weth), collateral);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        // Gas should be reasonable (adjust threshold as needed)
        assertLt(gasUsed, 500000, "Excessive gas consumption");
    }

    /// @notice Test rounding doesn't create value out of thin air
    function testFuzz_NoValueCreationFromRounding(
        uint256 borrowAmount,
        uint256 repayAmount
    ) public {
        borrowAmount = bound(borrowAmount, 1000e6, 10000e6);
        repayAmount = bound(repayAmount, 100e6, borrowAmount);

        // Setup
        uint256 collateral = 50 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral);
        vm.stopPrank();

        _setUserAccountData(
            address(debtManager),
            100000e8,
            0,
            65000e8,
            8000,
            7500,
            type(uint256).max
        );

        // Borrow
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrowUsdc(borrowAmount);

        (,uint256 debtAfterBorrow) = debtManager.getUserDebt(user);

        // Repay
        vm.startPrank(user);
        usdc.approve(address(debtManager), repayAmount);
        debtManager.repayUsdc(repayAmount);
        vm.stopPrank();

        (,uint256 debtAfterRepay) = debtManager.getUserDebt(user);

        // Debt reduction should not exceed repayment (allowing for small rounding)
        uint256 debtReduction = debtAfterBorrow - debtAfterRepay;
        assertApproxEqRel(debtReduction, repayAmount, 0.0001e18, "Excessive debt reduction");
    }
}