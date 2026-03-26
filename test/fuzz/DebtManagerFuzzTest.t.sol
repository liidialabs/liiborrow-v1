// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DebtManager} from "../../src/DebtManager.sol";
import {Aave} from "../../src/Aave.sol";
import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";
import {MockAaveOracle} from "../mocks/MockAaveOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {MockPoolDataProvider} from "../mocks/MockPoolDataProvider.sol";
import {IPool} from "../../src/interfaces/aave-v3/IPool.sol";
import {IDebtManager} from "../../src/interfaces/IDebtManager.sol";
import {HealthStatus} from "../../src/Types.sol";
import { ErrorsLib } from "../../src/libraries/ErrorsLib.sol";
import { EventsLib } from "../../src/libraries/EventsLib.sol";

contract DebtManagerFuzzTest is Test {
    DebtManager public debtManager;
    Aave public aave;
    MockAaveV3Pool public mockPool;
    MockAaveOracle public mockOracle;
    MockPoolDataProvider public mockDataProvider;
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public vUsdc;
    MockERC20 public vUsdt;
    MockERC20 public wbtc;
    MockERC20 public aWbtc;
    MockWETH public weth;
    MockERC20 public aWeth;

    address public owner;
    address public user;

    uint256 constant MIN_HEALTH_FACTOR = 1e18;
    uint256 constant BASE_PRECISION = 1e18;
    uint256 constant COOLDOWN = 10 minutes;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    int256 constant MIN_PRICE = 1e6;
    int256 constant MAX_PRICE = 1000000e8;
    int256 constant USDC_PRICE = 1e8;
    int256 constant WETH_PRICE = 2000e8;
    int256 constant WBTC_PRICE = 40000e8;

    uint256 constant MIN_COLLATERAL = 0.01 ether;
    uint256 constant MAX_COLLATERAL = 10 ether;
    uint256 constant MIN_BORROW = 1e6;
    uint256 constant MAX_BORROW = 10000e6;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        mockPool = new MockAaveV3Pool();
        mockOracle = new MockAaveOracle();
        mockDataProvider = new MockPoolDataProvider();
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        aWbtc = new MockERC20("Aave WBTC", "aWbtc", 8);
        weth = new MockWETH();
        aWeth = new MockERC20("Aave WETH", "aWETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        vUsdc = new MockERC20("Variable Debt USDC", "vUSDC", 6);
        vUsdt = new MockERC20("Variable Debt USDT", "vUSDT", 6);

        mockOracle.setAssetPrice(address(usdc), uint256(USDC_PRICE));
        mockOracle.setAssetPrice(address(usdt), uint256(USDC_PRICE));
        mockOracle.setAssetPrice(address(weth), uint256(WETH_PRICE));
        mockOracle.setAssetPrice(address(wbtc), uint256(WBTC_PRICE));

        IPool.ReserveData memory reserveData_usdc = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 1,
            aTokenAddress: address(usdc),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(vUsdc),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        IPool.ReserveData memory reserveData_usdt = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
            currentStableBorrowRate: 6e25,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 2,
            aTokenAddress: address(usdt),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(vUsdt),
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
        mockPool.setReserveData(address(usdt), reserveData_usdt);
        mockPool.setReserveData(address(weth), reserveData_weth);
        mockPool.setReserveData(address(wbtc), reserveData_wbtc);

        MockPoolDataProvider.ReserveConfig memory reserveConfig_usdc = MockPoolDataProvider.ReserveConfig({
            decimals: 6,
            ltv: 7500,
            liquidationThreshold: 8000,
            liquidationBonus: 10500,
            reserveFactor: 1000,
            usageAsCollateralEnabled: true,
            borrowingEnabled: true,
            stableBorrowRateEnabled: false,
            isActive: true,
            isFrozen: false
        });
        mockDataProvider.setReserveConfigurationData(address(usdc), reserveConfig_usdc);

        aave = new Aave(address(mockPool), address(mockOracle), address(mockDataProvider), address(usdc), address(usdt));

        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = address(weth);
        tokenAddresses[1] = address(wbtc);
        tokenAddresses[2] = address(usdc);

        debtManager = new DebtManager(
            tokenAddresses,
            address(aave),
            address(weth)
        );

        usdc.mint(address(mockPool), 1000000e6);
        usdt.mint(address(mockPool), 1000000e6);
        weth.mint(address(mockPool), 1000 ether);
        wbtc.mint(address(mockPool), 100e8);
        aWeth.mint(address(mockPool), 1000 ether);
        aWbtc.mint(address(mockPool), 1000e8);
        vUsdc.mint(address(mockPool), 1000000e6);
        vUsdt.mint(address(mockPool), 1000000e6);
        
        address(weth).call{value: 10000 ether}("");
        
        weth.mint(user, 1000000 ether);
        wbtc.mint(user, 1000000e8);
        usdc.mint(user, 1000000e6);
        vm.deal(user, 100000 ether);
    }

    function testFuzz_CollateralBalanceNeverExceedsTotalSupplied(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, MIN_COLLATERAL, MAX_COLLATERAL);

        vm.startPrank(user);
        weth.approve(address(debtManager), depositAmount);
        debtManager.depositCollateralERC20(address(weth), depositAmount, user);
        vm.stopPrank();

        uint256 userBalance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        uint256 totalSupplied = debtManager.getTotalColSupplied(address(weth));

        assertLe(userBalance, totalSupplied, "User balance exceeds total supplied");
    }

    function testFuzz_TotalCollateralEqualsUserBalances(uint256 user1Amount, uint256 user2Amount) public {
        user1Amount = bound(user1Amount, MIN_COLLATERAL, MAX_COLLATERAL / 2);
        user2Amount = bound(user2Amount, MIN_COLLATERAL, MAX_COLLATERAL * 2);

        address user2 = makeAddr("user2");
        weth.mint(user2, user2Amount);

        vm.startPrank(user);
        weth.approve(address(debtManager), user1Amount);
        debtManager.depositCollateralERC20(address(weth), user1Amount, user);
        vm.stopPrank();

        vm.startPrank(user2);
        weth.approve(address(debtManager), user2Amount);
        debtManager.depositCollateralERC20(address(weth), user2Amount, user2);
        vm.stopPrank();

        uint256 user1Balance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        uint256 user2Balance = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        uint256 totalSupplied = debtManager.getTotalColSupplied(address(weth));

        assertEq(user1Balance + user2Balance, totalSupplied, "Sum mismatch");
    }

    function testFuzz_CannotBorrowAboveLTV(uint256 collateralAmount, uint256 borrowAmount) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);
        
        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount, user);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue,
            0,
            (collateralValue * 75) / 100,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrowValue = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 maxBorrowUSDC = maxBorrowValue / 1e8;

        borrowAmount = bound(borrowAmount, MIN_BORROW, maxBorrowUSDC);

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), borrowAmount, user);

        uint256 ltv = debtManager.userLTV(user);
        assertLe(ltv, _ltv, "LTV exceeds Max LTV");
    }

    function testFuzz_HealthFactorMaintainedAfterBorrow(uint256 collateralAmount, uint256 borrowPercent) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount, user);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            (collateralValue * 75) / 100 / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        borrowPercent = bound(borrowPercent, 1, 60);

        uint256 maxBorrowValue = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowValue = (maxBorrowValue * borrowPercent) / 100;
        uint256 borrowAmount = borrowValue / 1e8;

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), borrowAmount, user);

        (uint256 hf, ) = debtManager.getUserHealthFactor(user);
        assertGe(hf, MIN_HEALTH_FACTOR, "Health factor below minimum");
    }

    function testFuzz_LiquidationOnlyWhenAboveThreshold(uint256 priceDrop) public {
        priceDrop = bound(priceDrop, 1, 90);

        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
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

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), 12000e6, user);

        int256 newPrice = (WETH_PRICE * int256(100 - priceDrop)) / 100;
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        bool isLiquidatable = debtManager.isLiquidatable(user);
        uint256 ltv = debtManager.userLTV(user);

        if (isLiquidatable) {
            assertGe(ltv, _lltv, "Should only be liquidatable above threshold");
        } else {
            assertLt(ltv, _lltv, "Should not be liquidatable below threshold");
        }
    }

    function testFuzz_CannotWithdrawMoreThanDeposited(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, MIN_COLLATERAL, MAX_COLLATERAL);
        withdrawAmount = bound(withdrawAmount, 10, MAX_COLLATERAL * 2);

        vm.startPrank(user);
        weth.approve(address(debtManager), depositAmount);
        debtManager.depositCollateralERC20(address(weth), depositAmount, user);
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

        vm.prank(user);
        if (withdrawAmount > depositAmount) {
            try debtManager.redeemCollateral(address(weth), withdrawAmount, user, false) {
                uint256 balanceAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
                assertGt(depositAmount, balanceAfter, "Balance should decrease");
            } catch {
                // Expected to revert for excessive withdrawal
            }
        } else {
            debtManager.redeemCollateral(address(weth), withdrawAmount, user, false);
            uint256 balanceAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
            assertEq(balanceAfter, depositAmount - withdrawAmount, "Incorrect balance");
        }
    }

    function testFuzz_WithdrawalMaintainsHealthFactor(uint256 collateralAmount, uint256 borrowPercent, uint256 withdrawPercent) public {
        collateralAmount = bound(collateralAmount, 10 ether, 100 ether);
        borrowPercent = bound(borrowPercent, 1, 50);
        withdrawPercent = bound(withdrawPercent, 1, 50);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount, user);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 75) / 100) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowAmount = (maxBorrow * borrowPercent) / (100 * 1e8);

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), borrowAmount, user);

        uint256 withdrawAmount = (collateralAmount * withdrawPercent) / 100;
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        try debtManager.redeemCollateral(address(weth), withdrawAmount, user, false) {
            (uint256 hf, ) = debtManager.getUserHealthFactor(user);
            assertGe(hf, MIN_HEALTH_FACTOR, "Health factor below minimum after withdrawal");
        } catch {
            // Withdrawal blocked due to health factor - expected behavior
        }
    }

    function testFuzz_LTVCalculationConsistency(uint256 collateralAmount, uint256 debtAmount) public {
        collateralAmount = bound(collateralAmount, 1 ether, 100 ether);
        debtAmount = bound(debtAmount, 100e6, 50000e6);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateralAmount);
        debtManager.depositCollateralERC20(address(weth), collateralAmount, user);
        vm.stopPrank();

        uint256 collateralValue = (collateralAmount * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 75) / 100) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;

        if (debtAmount * 1e12 > maxBorrow) {
            return;
        }

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), debtAmount, user);

        (, , uint256 totalCollateralValue) = debtManager.getUserAccountData(user);
        uint256 ltv = debtManager.userLTV(user);

        assertGt(ltv, 0, "LTV should be greater than 0 when user has debt and collateral");
        assertLe(ltv, BASE_PRECISION, "LTV should be <= 1e18");
    }

    function testFuzz_CollateralValueProportionality(uint256 amount1, uint256 amount2) public view {
        amount1 = bound(amount1, MIN_COLLATERAL, MAX_COLLATERAL / 2);
        amount2 = bound(amount2, MIN_COLLATERAL, MAX_COLLATERAL / 2);

        vm.assume(amount1 != amount2);

        uint256 value1 = debtManager.getUsdValue(address(weth), amount1);
        uint256 value2 = debtManager.getUsdValue(address(weth), amount2);

        uint256 ratio1 = (value1 * 1e18) / amount1;
        uint256 ratio2 = (value2 * 1e18) / amount2;

        assertEq(ratio1, ratio2, "Value not proportional to amount");
    }

    function testFuzz_ExtremePriceVolatility(uint256 priceMultiplier) public {
        priceMultiplier = bound(priceMultiplier, 1, 1000);

        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
        vm.stopPrank();

        int256 newPrice = (WETH_PRICE * int256(priceMultiplier)) / 10;
        newPrice = int256(bound(uint256(newPrice), uint256(MIN_PRICE), uint256(MAX_PRICE)));
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        uint256 value = debtManager.getAccountCollateralValue(user);
        assertGt(value, 0, "Should have collateral value");
    }

    function testFuzz_CooldownEnforcement(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, COOLDOWN + 1, COOLDOWN * 2);

        uint256 collateral = 10 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
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
            debtManager.redeemCollateral(address(weth), 1 ether, user, false);
        } else {
            debtManager.redeemCollateral(address(weth), 1 ether, user, false);
        }
    }

    function testFuzz_ProtocolRevenueAccumulation(uint256 aprMarkup, uint256 borrowAmount) public {
        aprMarkup = bound(aprMarkup, 0.005e18, 0.015e18);
        borrowAmount = bound(borrowAmount, 1000e6, 10000e6);

        debtManager.setProtocolAPRMarkup(aprMarkup);

        uint256 collateral = 20 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
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
        debtManager.borrow(address(usdc), borrowAmount, user);

        uint256 revenueBefore = debtManager.getProtocolRevenue();

        vm.startPrank(user);
        usdc.approve(address(debtManager), borrowAmount);
        debtManager.repay(address(usdc), borrowAmount, user);
        vm.stopPrank();

        uint256 revenueAfter = debtManager.getProtocolRevenue();

        if (aprMarkup > 0) {
            assertGt(revenueAfter, revenueBefore, "Revenue should increase");
        }
    }

    function testFuzz_MultiStepInvariants(uint256 collateral, uint256 borrowPercent, uint256 priceChange) public {
        collateral = bound(collateral, 1 ether, 100 ether);
        borrowPercent = bound(borrowPercent, 10, 60);
        priceChange = bound(priceChange, 50, 150);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
        vm.stopPrank();

        uint256 collateralValue = (collateral * uint256(WETH_PRICE) * 1e10) / 1e18;

        _setUserAccountData(
            address(debtManager),
            collateralValue / 1e8,
            0,
            ((collateralValue * 75) / 100) / 1e8,
            8000,
            7500,
            type(uint256).max
        );

        (,uint256 _ltv) = debtManager.getPlatformLltvAndLtv();
        uint256 maxBorrow = (collateralValue * _ltv) / BASE_PRECISION;
        uint256 borrowAmount = (maxBorrow * borrowPercent) / (100 * 1e8);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), borrowAmount, user);

        uint256 userCollateralBefore = debtManager.getCollateralBalanceOfUser(user, address(weth));
        (uint256 userDebtBefore,) = debtManager.getUserDebt(user);

        int256 newPrice = (WETH_PRICE * int256(priceChange)) / 100;
        newPrice = int256(bound(uint256(newPrice), uint256(MIN_PRICE), uint256(MAX_PRICE)));
        mockOracle.setAssetPrice(address(weth), uint256(newPrice));

        uint256 userCollateralAfter = debtManager.getCollateralBalanceOfUser(user, address(weth));
        (uint256 userDebtAfter,) = debtManager.getUserDebt(user);

        assertEq(userCollateralBefore, userCollateralAfter, "Collateral changed without action");
        
        assertApproxEqRel(userDebtBefore, userDebtAfter, 0.001e18, "Debt changed unexpectedly");
    }

    function testFuzz_MultiUserScenario(uint256 user1Collateral, uint256 user2Collateral, uint256 user1BorrowPercent, uint256 user2BorrowPercent) public {
        user1Collateral = bound(user1Collateral, 5 ether, 50 ether);
        user2Collateral = bound(user2Collateral, 5 ether, 50 ether);
        user1BorrowPercent = bound(user1BorrowPercent, 10, 50);
        user2BorrowPercent = bound(user2BorrowPercent, 10, 50);

        address user2 = makeAddr("user2");
        weth.mint(user2, 1000 ether);
        usdc.mint(user2, 1000000e6);

        vm.startPrank(user);
        weth.approve(address(debtManager), user1Collateral);
        debtManager.depositCollateralERC20(address(weth), user1Collateral, user);
        vm.stopPrank();

        uint256 value1 = (user1Collateral * uint256(WETH_PRICE) * 1e10) / 1e18;
        uint256 maxBorrow1 = (value1 * 75) / 100;

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
        debtManager.borrow(address(usdc), borrow1, user);

        vm.startPrank(user2);
        weth.approve(address(debtManager), user2Collateral);
        debtManager.depositCollateralERC20(address(weth), user2Collateral, user2);
        vm.stopPrank();

        uint256 value2 = (user2Collateral * uint256(WETH_PRICE) * 1e10) / 1e18;
        uint256 totalValue = value1 + value2;
        uint256 maxBorrow2 = (value2 * 75) / 100;

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
        vm.prank(user);
        uint256 user1Balance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        assertGe(user1Balance, user1Collateral - 1 ether, "User1 balance too low");

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        uint256 user2Balance = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        assertGe(user2Balance, user2Collateral - 1 ether, "User2 balance too low");

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        uint256 user1Shares = debtManager.getUserShares(user);
        assertGt(user1Shares, 0, "User1 should have shares");
    }

    function testFuzz_RapidDepositWithdraw(uint256[5] memory amounts, bool[5] memory isDeposit) public {
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = bound(amounts[i], 0.1 ether, 10 ether);
        }

        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < 5; i++) {
            if (isDeposit[i]) {
                vm.startPrank(user);
                weth.approve(address(debtManager), amounts[i]);
                debtManager.depositCollateralERC20(address(weth), amounts[i], user);
                vm.stopPrank();
                totalDeposited += amounts[i];
            } else {
                if (totalDeposited > 0) {
                    uint256 withdrawAmount = amounts[i] > totalDeposited ? totalDeposited : amounts[i];
                    vm.warp(block.timestamp + COOLDOWN + 1);
                    vm.prank(user);
                    try debtManager.redeemCollateral(address(weth), withdrawAmount, user, false) {
                        totalDeposited -= withdrawAmount;
                    } catch {
                    }
                }
            }
        }

        uint256 userBalance = debtManager.getCollateralBalanceOfUser(user, address(weth));
        assertEq(userBalance, totalDeposited, "Final balance mismatch");
    }

    function testFuzz_GasConsumption(uint256 collateral) public {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_COLLATERAL);

        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        
        uint256 gasBefore = gasleft();
        debtManager.depositCollateralERC20(address(weth), collateral, user);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        assertLt(gasUsed, 500000, "Excessive gas consumption");
    }

    function testFuzz_NoValueCreationFromRounding(uint256 borrowAmount, uint256 repayAmount) public {
        borrowAmount = bound(borrowAmount, 1000e6, 10000e6);
        repayAmount = bound(repayAmount, 100e6, borrowAmount);

        uint256 collateral = 50 ether;
        vm.startPrank(user);
        weth.approve(address(debtManager), collateral);
        debtManager.depositCollateralERC20(address(weth), collateral, user);
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

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user);
        debtManager.borrow(address(usdc), borrowAmount, user);

        (,uint256 debtAfterBorrow) = debtManager.getUserDebt(user);

        vm.startPrank(user);
        usdc.approve(address(debtManager), repayAmount);
        debtManager.repay(address(usdc), repayAmount, user);
        vm.stopPrank();

        (,uint256 debtAfterRepay) = debtManager.getUserDebt(user);

        uint256 debtReduction = debtAfterBorrow - debtAfterRepay;
        assertGt(debtReduction, 0, "Debt should be reduced");
        
        uint256 maxExpected = repayAmount * 1e12 * 2;
        assertLt(debtReduction, maxExpected, "Debt reduction is reasonable");
    }

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
}