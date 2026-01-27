// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DebtManager} from "../../src/DebtManager.sol";
import {Aave} from "../../src/Aave.sol";
import {MockAavePool} from "../mocks/MockAavePool.sol";
import {MockAaveOracle} from "../mocks/MockAaveOracle.sol";
import {MockPoolDataProvider} from "../mocks/MockPoolDataProvider.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";
import {IPool} from "../../src/interfaces/aave-v3/IPool.sol";
import {HealthStatus, UserCollateral, LiquidationEarnings} from "../../src/Types.sol";
import { ErrorsLib } from "../../src/libraries/ErrorsLib.sol";
import { EventsLib } from "../../src/libraries/EventsLib.sol";

contract DebtManagerTest is Test {
    DebtManager public debtManager;
    Aave public aave;
    MockAavePool public mockPool;
    MockAaveOracle public mockOracle;
    MockPoolDataProvider public mockPoolDataProvider;
    MockERC20 public usdc;
    MockERC20 public vUsdc;
    MockERC20 public wbtc;
    MockERC20 public aWbtc;
    MockWETH public weth;
    MockERC20 public aWeth;

    // Addresses
    address public owner;
    address public user1;
    address public user2;
    address public liquidator;
    address public treasury;

    // Constants matching contract
    uint256 constant MIN_HEALTH_FACTOR = 1e18;
    uint256 constant BASE_PRECISION = 1e18;
    uint256 private COOLDOWN;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    // Price feed values
    int256 constant USDC_PRICE = 1e8; // $1
    int256 constant WETH_PRICE = 2000e8; // $2000
    int256 constant WBTC_PRICE = 40000e8; // $40000

    function setUp() public {
        // Setup accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidator = makeAddr("liquidator");
        treasury = makeAddr("treasury");

        // Deploy mocks
        mockPool = new MockAavePool();
        mockOracle = new MockAaveOracle();
        mockPoolDataProvider = new MockPoolDataProvider();
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

        // Setup pool data provider
        MockPoolDataProvider.ReserveConfig memory reserveConfig_weth = MockPoolDataProvider.ReserveConfig({
            decimals: BASE_PRECISION,
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

        // Deploy Aave
        aave = new Aave(address(mockPool), address(mockOracle), address(mockPoolDataProvider), address(usdc));

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

        COOLDOWN = debtManager.getCoolDownPeriod();

        // Fund the pool with USDC for borrowing
        usdc.mint(address(mockPool), 1000000e6);
        weth.mint(address(mockPool), 1000 ether);
        wbtc.mint(address(mockPool), 100e8);
        aWeth.mint(address(mockPool), 1000 ether);
        aWbtc.mint(address(mockPool), 1000e8);
        vUsdc.mint(address(mockPool), 1000000e6);

        // Fund users
        weth.mint(user1, 100 ether);
        wbtc.mint(user1, 10e8);
        usdc.mint(user1, 100000e6);

        weth.mint(user2, 100 ether);
        usdc.mint(user2, 100000e6);

        usdc.mint(liquidator, 100000e6);
    }

    // Helper function to setup user account data
    function _setUserAccountData(
        address user,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) internal {
        mockPool.setUserAccountData(
            user,
            totalCollateralBase,
            totalDebtBase,
            availableBorrowsBase,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        );
    }

    // ============ CONSTRUCTOR TESTS ============

    function test_Constructor_SetsCorrectly() public view {
        assertEq(address(debtManager.pool()), address(mockPool));
        assertEq(address(debtManager.weth()), address(weth));
        assertEq(address(debtManager.aave()), address(aave));
    }

    function test_Constructor_RevertsOnNoCollateralParsed() public {
        address[] memory tokens = new address[](0);

        vm.expectRevert(
            ErrorsLib.DebtManager__CollateralAssetsNotParsed.selector
        );
        new DebtManager(tokens, address(aave), address(usdc), address(weth));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(weth);
        tokenAddresses[1] = address(0);

        vm.expectRevert(
            ErrorsLib.DebtManager__ZeroAddress.selector
        );
        new DebtManager(tokenAddresses, address(aave), address(usdc), address(weth));
    }

    // ============ DEPOSIT COLLATERAL ERC20 TESTS ============

    function test_DepositCollateralERC20_Success() public {
        uint256 depositAmount = 1e8;

        vm.startPrank(user1);
        wbtc.approve(address(debtManager), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit EventsLib.CollateralDeposited(user1, address(wbtc), depositAmount);
        
        debtManager.depositCollateralERC20(address(wbtc), depositAmount);
        vm.stopPrank();

        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(wbtc)), depositAmount);
        assertEq(debtManager.getTotalColSupplied(address(wbtc)), depositAmount);

        // balance check
        uint256 balance = aave.getSupplyBalance(address(debtManager), address(wbtc));
        assertEq(balance, depositAmount);
    }

    function test_DepositCollateralERC20_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.depositCollateralERC20(address(weth), 0);
    }

    function test_DepositCollateralERC20_RevertsOnZeroAddress() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__ZeroAddress.selector);
        debtManager.depositCollateralERC20(address(0), 1 ether);
    }

    function test_DepositCollateralERC20_RevertsOnUnallowedToken() public {
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(ErrorsLib.DebtManager__TokenNotSupported.selector, address(randomToken))
        );
        debtManager.depositCollateralERC20(address(randomToken), 1 ether);
    }

    function test_DepositCollateralERC20_MultipleDeposits() public {
        uint256 firstDeposit = 1 ether;
        uint256 secondDeposit = 2 ether;

        vm.startPrank(user1);
        weth.approve(address(debtManager), firstDeposit + secondDeposit);
        
        debtManager.depositCollateralERC20(address(weth), firstDeposit);
        debtManager.depositCollateralERC20(address(weth), secondDeposit);
        vm.stopPrank();

        assertEq(
            debtManager.getCollateralBalanceOfUser(user1, address(weth)),
            firstDeposit + secondDeposit
        );
    }

    // ============ DEPOSIT COLLATERAL ETH TESTS ============

    function test_DepositCollateralETH_Success() public {
        uint256 depositAmount = 1 ether;

        vm.deal(user1, depositAmount);
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit EventsLib.CollateralDeposited(user1, address(0), depositAmount);
        
        debtManager.depositCollateralETH{value: depositAmount}(depositAmount);

        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(0)), depositAmount);

        // balance check
        uint256 balance = aave.getSupplyBalance(address(debtManager), address(weth));
        assertEq(balance, depositAmount);

        // next Activity
        uint32 nextActivity = debtManager.getNextActivity(user1);
        assertGt(nextActivity, uint32(block.timestamp));
    }

    function test_DepositCollateralETH_RevertsOnMismatchedAmount() public {
        vm.deal(user1, 2 ether);
        
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__AmountNotEqual.selector);
        debtManager.depositCollateralETH{value: 2 ether}(1 ether);
    }

    function test_DepositCollateralETH_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.depositCollateralETH{value: 0}(0);
    }

    // ============ BORROW USDC TESTS ============

    function test_BorrowUsdc_Success() public {
        // First deposit collateral
        uint256 collateralAmount = 10 ether; // 10 ETH = $20,000
        _depositWETH(user1, collateralAmount);

        // Setup Aave pool state for borrowing
        _setUserAccountData(
            address(debtManager),
            20000e8, // $20k collateral
            0,
            13000e8, // Can borrow up to $13k (65% of $20k)
            8000,
            7500,
            type(uint256).max
        );

        uint256 borrowAmount = 5000e6; // Borrow $5000

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(borrowAmount);

        // Check debt was recorded
        (uint256 aaveDebt,) = debtManager.getUserDebt(user1);
        assertEq(aaveDebt, 5000e6);
        uint256 userShares = debtManager.getUserShares(user1);
        assertEq(userShares, 5000e18);

        // get HealthFactor
        uint256 expectedHf = (14000e18 * BASE_PRECISION) / 5000e18;
        uint256 hf = debtManager.getHealthFactor(user1);
        assertEq(hf, expectedHf);

        // vUsdc balance
        uint256 balance = aave.getVariableDebt(address(debtManager), address(usdc));
        assertEq(balance, borrowAmount);

        // get total shares
        uint256 shares = debtManager.getTotalDebtShares();
        assertEq(shares, 5000e18);

        // Second borrow
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(borrowAmount);

        (uint256 _aaveDebt, uint256 _allDebt) = debtManager.getUserDebt(user1);
        assertEq(_aaveDebt, borrowAmount * 2);
        assertEq(_allDebt, 10050e6);

        shares = debtManager.getTotalDebtShares();
        assertEq(shares, 10000e18);
    }

    function test_BorrowUsdc_RevertsWithNoCollateral() public {
        // Setup Aave pool state for borrowing
        _setUserAccountData(
            address(debtManager),
            20000e8, // $20k collateral
            0,
            15000e8, // Can borrow up to $13k (65% of $20k)
            8000,
            7500,
            type(uint256).max
        );

        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NoCollateralSupplied.selector);
        debtManager.borrowUsdc(1000e6);
    }

    function test_BorrowUsdc_RevertsOnHfBreak() public {
        uint256 collateralAmount = 10 ether; // $20k
        _depositWETH(user2, collateralAmount);
        
        // Borrow close to limit
        _setUserAccountData(address(debtManager), 20000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(10000e6);

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(usdc), 1538e8);

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        vm.expectRevert(ErrorsLib.DebtManager__AlreadyAtBreakingPoint.selector);  
        debtManager.borrowUsdc(10000e6);      
    }

    function test_BorrowUsdc_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.borrowUsdc(0);
    }

    function test_BorrowUsdc_CapsAtMaxBorrowAmount() public {
        uint256 collateralAmount = 10 ether;
        _depositWETH(user1, collateralAmount);

        _setUserAccountData(
            address(debtManager),
            20000e8,
            0,
            15000e8, // Max $13k
            8000,
            7500,
            type(uint256).max
        );

        // get platform lltv & ltv
        (uint256 lltv, uint256 ltv) = debtManager.getPlatformLltvAndLtv();
        assertEq(lltv, 0.7e18);
        assertEq(ltv, 0.65e18);

        (uint256 value, uint256 amount) = debtManager.getUserMaxBorrow(user1);
        assertEq(value, 13000 ether);
        assertEq(amount, 13000e6);

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        // Try to borrow more than max, should cap at max
        debtManager.borrowUsdc(20000e6);

        (uint256 _aave,) = debtManager.getUserDebt(user1);
        assertEq(_aave, 13000e6);
    }

    function test_BorrowUsdc_EnforcesCooldown() public {
        uint256 collateralAmount = 10 ether;
        _depositWETH(user1, collateralAmount);

        _setUserAccountData(
            address(debtManager),
            20000e8,
            0,
            13000e8,
            8000,
            7500,
            type(uint256).max
        );

        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__CoolDownActive.selector);
        debtManager.borrowUsdc(1000e6);
    }

    // ============ REPAY USDC TESTS ============

    function test_RepayUsdc_Success() public {
        // Setup: deposit, borrow, then repay
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 5000e6;
        
        _depositWETH(user1, collateralAmount);
        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(borrowAmount);

        // vUsdc balance after borrow
        uint256 balance = aave.getVariableDebt(address(debtManager), address(usdc));
        assertEq(balance, borrowAmount);

        // platform debt
        uint256 expectedAllDebt = (balance * (1e18 + 5e15)) / 1e18;
        (uint256 _aaveDebt, uint256 allDebt) = debtManager.getPlatformDebt();
        assertEq(balance, _aaveDebt);
        assertEq(expectedAllDebt, allDebt);

        // Now repay
        uint256 repayAmount = 2010e6;
        
        vm.startPrank(user1);
        usdc.approve(address(debtManager), repayAmount);
        
        vm.expectEmit(true, false, false, false);
        emit EventsLib.RepayUsdc(user1, repayAmount, 0);
        
        debtManager.repayUsdc(repayAmount);
        vm.stopPrank();

        uint256 aaveCut = (repayAmount * 1e18) / (1e18 + 5e15);
        uint256 platformCut = repayAmount - aaveCut;
        uint256 newBorrowBalance = balance - aaveCut;

        // vUsdc balance after repay
        uint256 balanceAfter = aave.getVariableDebt(address(debtManager), address(usdc));
        assertEq(balanceAfter, newBorrowBalance);

        // Debt should be reduced
        (uint256 aaveDebt,) = debtManager.getPlatformDebt();
        (uint256 userAaveDebt,) = debtManager.getUserDebt(user1);
        assertEq(userAaveDebt, aaveDebt);

        // Revenue
        uint256 revenue = debtManager.getProtocolRevenue();
        assertEq(revenue, platformCut);
    }

    function test_RepayUsdc_RevertsWithNoDebt() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NoAssetBorrowed.selector);
        debtManager.repayUsdc(1000e6);
    }

    function test_RepayUsdc_CapsAtUserDebt() public {
        // Setup borrow
        uint256 collateralAmount = 10 ether;
        uint256 borrowAmount = 5000e6;
        
        _depositWETH(user1, collateralAmount);
        _setUserAccountData(address(debtManager), 20000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(borrowAmount);

        (uint256 userAaveDebt,) = debtManager.getUserDebt(user1);

        // Try to repay more than debt
        uint256 maxRepay = userAaveDebt * 2;
        vm.startPrank(user1);
        usdc.approve(address(debtManager), maxRepay);
        debtManager.repayUsdc(maxRepay); // Should only repay actual debt
        vm.stopPrank();

        (uint256 _aaveDebt,) = debtManager.getUserDebt(user1);
        assertEq(_aaveDebt, 0);
    }

    function test_RepayUsdc_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.repayUsdc(0);
    }

    // ============ REDEEM COLLATERAL TESTS ============

    function test_RedeemCollateral_Success_ERC20() public {
        uint256 depositAmount = 10 ether;
        _depositWETH(user1, depositAmount);

        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);

        assertEq(
            aave.getSupplyBalance(address(debtManager), address(weth)), 
            depositAmount
        );

        uint256 redeemAmount = 5 ether;
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.redeemCollateral(address(weth), redeemAmount, false);

        assertEq(
            debtManager.getCollateralBalanceOfUser(user1, address(weth)),
            depositAmount - redeemAmount
        );
        assertEq(
            aave.getSupplyBalance(address(debtManager), address(weth)), 
            5 ether
        );

        // try redeeming above supply
        uint256 excessRedeemAmount = 6 ether;

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.redeemCollateral(address(weth), excessRedeemAmount, false);

        assertEq(
            debtManager.getCollateralBalanceOfUser(user1, address(weth)),
            0
        );
        assertEq(
            aave.getSupplyBalance(address(debtManager), address(weth)), 
            0
        );
    }

    function test_RedeemCollateral_Success_ETH() public {
        uint256 depositAmount = 2 ether;

        vm.deal(user1, depositAmount);
        
        vm.prank(user1);
        debtManager.depositCollateralETH{value: depositAmount}(depositAmount);

        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);

        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(0)), depositAmount);
        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(weth)), depositAmount);

        // balance check
        uint256 balance = aave.getSupplyBalance(address(debtManager), address(weth));
        assertEq(balance, depositAmount);

        // redeem
        uint256 redeemAmount = 1 ether;
        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(user1);
        debtManager.redeemCollateral(address(weth), redeemAmount, true);

        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(0)), redeemAmount);
        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(weth)), redeemAmount);

        // balance check
        balance = aave.getSupplyBalance(address(debtManager), address(weth));
        assertEq(balance, redeemAmount);
    }

    function test_RedeemCollateral_RevertsWithInsufficientCollateral() public {
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__InsufficientCollateral.selector);
        debtManager.redeemCollateral(address(weth), 1 ether, false);
    }

    function test_RedeemCollateral_EnforcesCooldown() public {
        uint256 depositAmount = 10 ether;
        _depositWETH(user1, depositAmount);

        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__CoolDownActive.selector);
        debtManager.redeemCollateral(address(weth), 1 ether, false);
    }

    function test_RedeemCollateral_CapsAtMaxWithdrawable() public {
        // Deposit collateral and borrow
        uint256 depositAmountWeth = 0.8 ether; // $1.6k
        _depositWETH(user1, depositAmountWeth);
        // deposit wbtc
        uint256 depositAmountWbtc = 0.46e8; // $18.4k
        vm.startPrank(user1);
        wbtc.approve(address(debtManager), depositAmountWbtc);
        debtManager.depositCollateralERC20(address(wbtc), depositAmountWbtc);
        vm.stopPrank();
        
        _setUserAccountData(address(debtManager), 20000e8, 0, 12000e8, 8000, 7500, type(uint256).max);
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(10000e6); // Borrow $10k

        uint256 wethBal = debtManager.getCollateralBalanceOfUser(user1, address(weth));
        assertEq(wethBal, depositAmountWeth);
        uint256 wbtcBal = debtManager.getCollateralBalanceOfUser(user1, address(wbtc));
        assertEq(wbtcBal, depositAmountWbtc);

        // user account data
        (
            uint256 _totalCollateral,
            uint256 _totalDebt,
            uint256 _healthFactor
        ) = debtManager.getUserAccountData(user1);
        assertEq(_totalCollateral, 20000e8);
        assertEq(_totalDebt, 10000e8);
        assertGt(_healthFactor, MIN_HEALTH_FACTOR);

        // user total debt
        uint256 totalDebtOwed = debtManager.getUserTotalDebt(user1);
        assertEq(totalDebtOwed, 10050 ether);

        // max Withdrawal amount
        uint256 maxWeth = debtManager.getUserMaxCollateralWithdrawAmount(user1, address(weth));
        assertEq(maxWeth, 0.8 ether);
        uint256 maxWbtc = debtManager.getUserMaxCollateralWithdrawAmount(user1, address(wbtc));
        assertEq(maxWbtc, 0.075e8);

        // Try to redeem all Weth collateral (should be possible as wont break HF)
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.redeemCollateral(address(weth), depositAmountWeth, false);

        // Should still have some collateral left to maintain HF
        uint256 remainingWeth = debtManager.getCollateralBalanceOfUser(user1, address(weth));
        assertEq(remainingWeth, 0);
        uint256 remainingWbtc = debtManager.getCollateralBalanceOfUser(user1, address(wbtc));
        assertEq(remainingWbtc, depositAmountWbtc);
    }

    function test_RedeemCollateral_OnlyAllowedTokens() public {
        uint256 depositAmount = 1 ether;
        MockERC20 tokenx = new MockERC20("Token X", "xTok", 8);

        vm.prank(user1);
        vm.expectRevert();
        debtManager.redeemCollateral(address(tokenx), depositAmount, false);
    }

    function test_RedeemCollateral_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.redeemCollateral(address(weth), 0, false);
    }

    // ============ LIQUIDATION TESTS ============

    function test_Liquidate_Success_ERC20() public {
        // Setup user with liquidatable position
        uint256 collateralAmount = 10 ether; // $20k
        _depositWETH(user2, collateralAmount);
        
        // Borrow close to limit
        _setUserAccountData(address(debtManager), 20000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(10000e6);

        // hf before price drop
        uint256 hfBefore = debtManager.getHealthFactor(user2);
        assertGt(hfBefore, MIN_HEALTH_FACTOR);

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(weth), 1400e8);

        // hf after price drop
        uint256 hfAfter = debtManager.getHealthFactor(user2);
        assertLt(hfAfter, MIN_HEALTH_FACTOR);

        // Now user should be liquidatable
        // Liquidator repays debt
        uint256 repayAmount = 6000e6;
        
        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), repayAmount);
        
        vm.expectEmit(true, true, true, false);
        emit EventsLib.Liquidated(liquidator, user2, address(weth), repayAmount, 0);
        
        debtManager.liquidate(user2, address(weth), repayAmount, false);
        vm.stopPrank();

        // User's collateral should be reduced
        uint256 remainingCollateral = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        assertLt(remainingCollateral, collateralAmount);
        assertEq(remainingCollateral, 6.2125 ether);

        // liquidator balance
        uint256 liqBal = weth.balanceOf(liquidator);
        assertEq(liqBal, 3.75 ether);

        // platform Earning
        uint256 expectedEarn = 0.0375 ether;
        uint256 earn = debtManager.getLiquidationRevenueSpecific(address(weth));
        assertEq(earn, expectedEarn);

        LiquidationEarnings[] memory liquidationEarnings = debtManager.getLiquidationRevenue();
        assertEq(liquidationEarnings[0].amount, expectedEarn);
        assertEq(liquidationEarnings[0].token, "WETH");
    }

    function test_Liquidate_Success_ETH() public {
        uint256 depositAmount = 10 ether;

        vm.deal(user2, depositAmount);
        // deposit ETH
        vm.prank(user2);
        debtManager.depositCollateralETH{value: depositAmount}(depositAmount);

        // Borrow close to limit
        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(10000e6);

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(weth), 1400e8);

        // Now user should be liquidatable
        // Liquidator repays debt
        uint256 repayAmount = 5000e6;
        
        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), repayAmount);
        
        vm.expectEmit(true, true, true, false);
        emit EventsLib.Liquidated(liquidator, user2, address(weth), repayAmount, 0);
        
        debtManager.liquidate(user2, address(weth), repayAmount, true);
        vm.stopPrank();

        // User's collateral should be reduced
        uint256 expectedRemaining = 6.2125 ether;
        uint256 remainingCollateral = debtManager.getCollateralBalanceOfUser(user2, address(weth));
        assertLt(remainingCollateral, depositAmount);
        assertEq(remainingCollateral, expectedRemaining);
        remainingCollateral = debtManager.getCollateralBalanceOfUser(user2, address(0));
        assertLt(remainingCollateral, depositAmount);
        assertEq(remainingCollateral, expectedRemaining);

        // liquidator balance
        uint256 liqBal = liquidator.balance;
        assertEq(liqBal, 3.75 ether);

        // platform Earning
        uint256 expectedEarn = 0.0375 ether;
        uint256 earn = debtManager.getLiquidationRevenueSpecific(address(weth));
        assertEq(earn, expectedEarn);

        LiquidationEarnings[] memory liquidationEarnings = debtManager.getLiquidationRevenue();
        assertEq(liquidationEarnings[0].amount, expectedEarn);
        assertEq(liquidationEarnings[0].token, "WETH");
    }

    function test_Liquidate_RevertsWhenUserNotLiquidatable() public {
        // Healthy position
        uint256 collateralAmount = 10 ether;
        _depositWETH(user2, collateralAmount);

        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);

        // get user LTV & check if liquidatable
        uint256 userLtv = debtManager.userLTV(user2);
        assertEq(userLtv, type(uint256).max);
        bool isLiquidatable = debtManager.isLiquidatable(user2);
        assertEq(isLiquidatable, false);

        vm.prank(liquidator);
        vm.expectRevert(ErrorsLib.DebtManager__UserNotLiquidatable.selector);
        debtManager.liquidate(user2, address(weth), 1000e6, false);
    }

    function test_Liquidate_RevertsOnInsufficientCollateral() public {
        // Setup liquidatable position with small collateral
        uint256 collateralAmount = 1 ether;
        _depositWETH(user2, collateralAmount);
        
        _setUserAccountData(address(debtManager), 2000e8, 0, 1300e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(1200e6);

        // Price crash
        mockOracle.setAssetPrice(address(usdc), 1200e8);

        // Try to liquidate more than available collateral
        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), 10000e6);
        
        vm.expectRevert(ErrorsLib.DebtManager__InsufficientCollateral.selector);
        debtManager.liquidate(user2, address(weth), 10000e6, false);
        vm.stopPrank();
    }

    function test_Liquidate_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.liquidate(user1, address(weth), 0, false);
    }

    function test_Liquidate_RevertsOnBreakingHF() public {
        // Setup user with liquidatable position
        uint256 collateralAmount = 1 ether; // $2k
        _depositWETH(user2, collateralAmount);
        
        // Borrow close to limit
        _setUserAccountData(address(debtManager), 2000e8, 0, 1500e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(1200e6);

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(weth), 1700e8);

        // Now user should be liquidatable
        // Liquidator repays debt
        uint256 repayAmount = 30e6;
        
        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), repayAmount);
        
        vm.expectRevert(ErrorsLib.DebtManager__BreaksHealthFactor.selector);
        debtManager.liquidate(user2, address(weth), repayAmount, false);

        vm.stopPrank();
    }

    // Withdraw Revenue

    function test_WithdrawRevenue_LiquidationRevenue_Success() public {
        // Simulate some revenue
        uint256 depositAmount = 10 ether;
        _depositWETH(user2, depositAmount);
        
        _setUserAccountData(address(debtManager), 20000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(10000e6);

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(weth), 1400e8);

        // Liquidator repays debt
        uint256 repayAmount = 5000e6;
        
        vm.startPrank(liquidator);
        usdc.approve(address(debtManager), repayAmount);
        debtManager.liquidate(user2, address(weth), repayAmount, false);
        vm.stopPrank();

        uint256 revenueBefore = debtManager.getLiquidationRevenueSpecific(address(weth));
        assertGt(revenueBefore, 0);

        // Withdraw revenue
        uint256 wethBalBefore = weth.balanceOf(treasury);
        
        vm.expectEmit(true, false, false, false);
        emit EventsLib.RevenueWithdrawn(treasury, address(weth), revenueBefore, 0);
        
        debtManager.withdrawRevenue(treasury, address(weth), revenueBefore);

        uint256 wethBalAfter = weth.balanceOf(treasury);
        assertEq(wethBalAfter - wethBalBefore, revenueBefore);

        uint256 revenueAfter = debtManager.getLiquidationRevenueSpecific(address(weth));
        assertEq(revenueAfter, 0);
    }

    function test_WithdrawRevenue_RepayRevenue_Success() public {
        // Simulate some revenue
        uint256 depositAmount = 10 ether;
        _depositWETH(user2, depositAmount);
        
        _setUserAccountData(address(debtManager), 20000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user2);
        debtManager.borrowUsdc(10000e6);

        // Simulate some repayments to generate revenue
        uint256 repayAmount = 2010e6;
        
        vm.startPrank(user2);
        usdc.approve(address(debtManager), repayAmount);
        debtManager.repayUsdc(repayAmount);
        vm.stopPrank();

        uint256 revenueBefore = debtManager.getProtocolRevenue();
        assertGt(revenueBefore, 0);

        // Withdraw revenue
        uint256 usdcBalBefore = usdc.balanceOf(treasury);
        
        vm.expectEmit(true, false, false, false);
        emit EventsLib.RevenueWithdrawn(treasury, address(usdc), revenueBefore, 1);
        
        debtManager.withdrawRevenue(treasury, address(usdc), revenueBefore);

        uint256 usdcBalAfter = usdc.balanceOf(treasury);
        assertEq(usdcBalAfter - usdcBalBefore, revenueBefore);

        uint256 revenueAfter = debtManager.getProtocolRevenue();
        assertEq(revenueAfter, 0);
    }

    function test_WithdrawRevenue_RevertsOnInsufficientRevenue() public {
        // Repayment Revenue
        vm.expectRevert(ErrorsLib.DebtManager__InsufficientAmountToWithdraw.selector);
        debtManager.withdrawRevenue(treasury, address(weth), 1 ether);
        // Liquidation Revenue
        vm.expectRevert(ErrorsLib.DebtManager__InsufficientAmountToWithdraw.selector);
        debtManager.withdrawRevenue(treasury, address(usdc), 1e6);
    }

    function test_WithdrawRevenue_RevertOnZeroAmount() public {
        vm.expectRevert(ErrorsLib.DebtManager__NeedsMoreThanZero.selector);
        debtManager.withdrawRevenue(treasury, address(weth), 0);
    }

    function test_WithdrawRevenue_RevertOnInvalidToken() public {
        MockERC20 tokenx = new MockERC20("Token X", "xTok", 8);
        vm.expectRevert(
            abi.encodeWithSelector(ErrorsLib.DebtManager__TokenNotSupported.selector, address(tokenx))
        );
        debtManager.withdrawRevenue(treasury, address(tokenx), 1 ether);
    }

    function test_WithdrawRevenue_RevertOnInvalidRecipient() public {
        // recipient zero address
        vm.expectRevert(ErrorsLib.DebtManager__ZeroAddress.selector);
        debtManager.withdrawRevenue(address(0), address(weth), 1 ether);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_GetAccountCollateralValue_MultipleTokens() public {
        _depositWETH(user1, 5 ether); // $10k
        
        vm.startPrank(user1);
        wbtc.approve(address(debtManager), 1e8);
        debtManager.depositCollateralERC20(address(wbtc), 1e8); // $40k
        vm.stopPrank();

        uint256 totalValue = debtManager.getAccountCollateralValue(user1);
        assertEq(totalValue, 50000e18); // $50k in 1e18 precision
    }

    function test_GetCollateralAmount_CalculatesCorrectly() public view {
        uint256 repayValue = 1000e18; // $1000
        uint256 collateralAmount = debtManager.getCollateralAmount(address(weth), repayValue);
        assertEq(collateralAmount, 0.5 ether);
    }

    function test_GetPlatformLltvAndLtv_ReturnsCorrectValue() public {
        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);

        (uint256 lltv, uint256 ltv) = debtManager.getPlatformLltvAndLtv();
        assertEq(lltv, 0.7e18);
        assertEq(ltv, 0.65e18);
    }

    function test_GetCollateralTokens_ReturnsCorrectArray() public view {
        address[] memory tokens = debtManager.getCollateralTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(weth));
        assertEq(tokens[1], address(wbtc));
        assertEq(tokens[2], address(usdc));
    }

    function test_GetUserHealthFactor_CalculatesCorrectly() public {
        uint256 collateralAmount = 1 ether; // $20k
        _depositWETH(user1, collateralAmount);
        
        _setUserAccountData(address(debtManager), 2000e8, 0, 1500e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(1200e6); // Borrow $1.2k

        (, HealthStatus healthy) = debtManager.getUserHealthFactor(user1);
        assertEq(uint8(healthy), uint8(HealthStatus.Healthy));

        // Borrow More
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(100e6); // Borrow $100

        (, HealthStatus danger) = debtManager.getUserHealthFactor(user1);
        assertEq(uint8(danger), uint8(HealthStatus.Danger));

        // Simulate price crash - ETH drops to $1400
        mockOracle.setAssetPrice(address(usdc), 1700e8);

        (, HealthStatus liquidate) = debtManager.getUserHealthFactor(user1);
        assertEq(uint8(liquidate), uint8(HealthStatus.Liquidatable));
    }

    function test_IsLiquidatable_ReturnsTrueWhenAboveLTV() public {
        uint256 collateralAmount = 1 ether;
        _depositWETH(user1, collateralAmount);
        
        _setUserAccountData(address(debtManager), 2000e8, 0, 15000e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(1200e6);

        // Price crash
        mockOracle.setAssetPrice(address(usdc), 1700e8);

        assertTrue(debtManager.isLiquidatable(user1));
    }

    function test_UserLTV_CalculatesCorrectly() public {
        uint256 collateralAmount = 1 ether; // $2k
        _depositWETH(user1, collateralAmount);
        
        _setUserAccountData(address(debtManager), 2000e8, 0, 1500e8, 8000, 7500, type(uint256).max);
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(1200e6); // Borrow $1.2k

        uint256 ltv = debtManager.userLTV(user1);
        // LTV = 1200 / 2000 = 0.6 = 60%
        assertEq(ltv, 0.6e18);

        // for user with no borrows
        assertEq(debtManager.userLTV(user2), type(uint256).max);
    }

    function test_GetAssetUsdValue_CalculateCorrectly() public view {
        // fetch wbtc value for 2.5 tokens
        uint256 amount = 2.5e8;
        uint256 value = debtManager.getUsdValue(address(wbtc), amount);
        uint256 expectedValue = (amount * uint256(WBTC_PRICE) * ADDITIONAL_FEED_PRECISION) / 1e8;
        assertEq(value, expectedValue);
    }

    function test_GetAssetPrice_FetchCorrectly() public {
        // fetch wbtc price
        uint256 price = debtManager.getAssetPrice(address(wbtc));
        assertEq(price, uint256(WBTC_PRICE));

        // revert on not supported token
        MockERC20 newCollateral = new MockERC20("Token X", "xTok", 18);
        vm.expectRevert();
        debtManager.getAssetPrice(address(newCollateral));

        // revert on zero address
        vm.expectRevert();
        debtManager.getAssetPrice(address(0));
    }

    function test_GetUserSuppliedCollateralAmount_FullData() public {
        // deposit Weth
        uint256 collateralAmount = 10 ether;        
        _depositWETH(user1, collateralAmount);
        // deposit wbtc
        uint256 depositAmount = 1e8;
        vm.startPrank(user1);
        wbtc.approve(address(debtManager), depositAmount);        
        debtManager.depositCollateralERC20(address(wbtc), depositAmount);
        vm.stopPrank();

        // check
        UserCollateral[] memory userCollateral = debtManager.getUserSuppliedCollateralAmount(user1);
        assertEq(userCollateral[0].token, "WETH");
        assertEq(userCollateral[0].amount, collateralAmount);
        assertEq(userCollateral[1].token, "WBTC");
        assertEq(userCollateral[1].amount, depositAmount);
    }

    function test_GetMaxWithdrawableAmount_RevertOnZeroCollateral() public {
        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);

        vm.expectRevert(ErrorsLib.DebtManager__InsufficientCollateral.selector);
        debtManager.getUserMaxCollateralWithdrawAmount(user1, address(wbtc));
    }

    function test_GetCollateralToSeize_CalculatesCorrectly() public view {
        uint256 repayValue = 1000e18; // $1000
        uint256 collateralToSeize = debtManager.getCollateralAmountLiquidate(address(weth), repayValue);
        // calculation: (1000 / 2000) * 1.05 = 0.525 ETH
        assertEq(collateralToSeize, 0.525 ether);
    }

    function test_GetAssetLiquidationBonus_ReturnsCorrectly() public view {
        uint256 bonus = debtManager.getLiquidationBonus(address(weth));
        uint expctedBonus = 0.05e18;
        assertEq(bonus, expctedBonus);
    }

    // ============ ONLYOWNER TESTS ============

    function test_SetProtocolAPRMarkup_OnlyOwner() public {
        uint256 newMarkup = 0.02e18; // 2%
        debtManager.setProtocolAPRMarkup(newMarkup);
        assertEq(debtManager.getProtocolAPRMarkup(), newMarkup);
    }

    function test_SetProtocolAPRMarkup_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        debtManager.setProtocolAPRMarkup(0.02e18);
    }

    function test_SetProtocolAPRMarkup_RevertsForBelowBaseApr() public {
        uint256 newMarkup = 0.002e18; // 0.2%
        vm.expectRevert();
        debtManager.setProtocolAPRMarkup(newMarkup);
    }

    function test_SetLiquidationFee_OnlyOwner() public {
        uint256 newMarkup = 0.02e18; // 2%
        debtManager.setLiquidationFee(newMarkup);
        assertEq(debtManager.getLiquidationFee(), newMarkup);
    }

    function test_SetLiquidationFee_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        debtManager.setLiquidationFee(0.02e18);
    }

    function test_SetLiquidationFee_RevertsForBelowBaseApr() public {
        uint256 newMarkup = 0.002e18; // 0.2%
        vm.expectRevert();
        debtManager.setLiquidationFee(newMarkup);
    }

    function test_SetCoolDownPeriod_OnlyOwner() public {
        uint256 newMarkup = 15 minutes; // 900 seconds
        debtManager.setCoolDownPeriod(newMarkup);
        assertEq(debtManager.getCoolDownPeriod(), newMarkup);
    }

    function test_SetCoolDownPeriod_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        debtManager.setCoolDownPeriod(15 minutes);
    }

    function test_SetCoolDownPeriod_RevertsForBelowBaseApr() public {
        uint256 newMarkup = 31 minutes; // 1860 seconds
        vm.expectRevert();
        debtManager.setCoolDownPeriod(newMarkup);
    }

    function test_ProtocolRevenueAccrues() public {
        // Setup with APR markup
        debtManager.setProtocolAPRMarkup(0.01e18); // 1%

        uint256 collateralAmount = 10 ether;
        _depositWETH(user1, collateralAmount);
        
        _setUserAccountData(address(debtManager), 20000e8, 0, 13000e8, 8000, 7500, type(uint256).max);
        
        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(user1);
        debtManager.borrowUsdc(5000e6);

        // Repay
        vm.startPrank(user1);
        usdc.approve(address(debtManager), 5000e6);
        debtManager.repayUsdc(5000e6);
        vm.stopPrank();

        // Protocol should have accrued revenue
        uint256 revenue = debtManager.getProtocolRevenue();
        assertGt(revenue, 0);
    }

    function test_AddCollateral_OnlyOwner() public {
        MockERC20 newCollateral = new MockERC20("Token X", "xTok", 18);

        debtManager.addCollateralAsset(address(newCollateral));
        assertEq(debtManager.checkIfTokenSupported(address(newCollateral)), true);
    }

    function test_AddCollateral_RevertsForNonOwner() public {
        MockERC20 newCollateral = new MockERC20("Token X", "xTok", 18);

        vm.prank(user1);
        vm.expectRevert();
        debtManager.addCollateralAsset(address(newCollateral));
    }

    function test_AddCollateral_RevertsOnZeroAddress() public {
        vm.expectRevert();
        debtManager.addCollateralAsset(address(0));
    }

    function test_PauseCollateralActivity_OnlyOwner() public {
        // pause
        debtManager.pauseCollateralActivity(address(weth));
        assertEq(debtManager.checkIfCollateralPaused(address(weth)), true);
        // remove
        vm.prank(user1);
        vm.expectRevert();
        debtManager.depositCollateralERC20(address(weth), 1 ether);
    }

    function test_PauseCollateralActivity_RevertsForNonOwner() public {
        // try pausing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.pauseCollateralActivity(address(weth));
    }

    function test_PauseCollateralActivity_RevertsOnZeroAdress() public {
        // pause
        vm.expectRevert();
        debtManager.pauseCollateralActivity(address(0));
    }

    function test_PauseCollateralActivity_RevertsOnAlreadyPaused() public {
        // pause
        debtManager.pauseCollateralActivity(address(weth));
        // try pausing again
        vm.expectRevert();
        debtManager.pauseCollateralActivity(address(weth));
    }

    function test_UnPauseCollateralActivity_OnlyOwner() public {
        // pause
        debtManager.pauseCollateralActivity(address(weth));
        assertEq(debtManager.checkIfCollateralPaused(address(weth)), true);
        // unpause
        debtManager.unPauseCollateralActivity(address(weth));
        assertEq(debtManager.checkIfCollateralPaused(address(weth)), false);
    }

    function test_UnPauseCollateralActivity_RevertsForNonOwner() public {
        debtManager.pauseCollateralActivity(address(weth));

        // try pausing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.unPauseCollateralActivity(address(weth));
    }

    function test_UnPauseCollateralActivity_RevertsOnZeroAdress() public {
        // pause
        vm.expectRevert();
        debtManager.unPauseCollateralActivity(address(0));
    }

    function test_UnPauseCollateralActivity_RevertsOnNotPaused() public {
        // try unpausing when not paused
        vm.expectRevert();
        debtManager.unPauseCollateralActivity(address(weth));
    }

    function test_PauseContract_OnlyOwner() public {
        // pause
        debtManager.pause();
        // try depositing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.depositCollateralERC20(address(wbtc), 1e8);
    }

    function test_PauseContract_RevertsForNonOwner() public {
        // try pausing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.pause();
    }

    function test_UnPauseContract_OnlyOwner() public {
        uint256 depositAmount = 1e8;

        // pause
        debtManager.pause();
        // try depositing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.depositCollateralERC20(address(wbtc), depositAmount);

        // unpause
        debtManager.unpause();
        // try deposting again
        vm.startPrank(user1);
        wbtc.approve(address(debtManager), depositAmount);
        debtManager.depositCollateralERC20(address(wbtc), depositAmount);
        vm.stopPrank();

        assertEq(debtManager.getCollateralBalanceOfUser(user1, address(wbtc)), depositAmount);
    }

    function test_UnPauseContract_RevertsForNonOwner() public {
        // pause
        debtManager.pause();

        // try pausing
        vm.prank(user1);
        vm.expectRevert();
        debtManager.unpause();
    }

    // ============ HELPER FUNCTIONS ============

    function _depositWETH(address user, uint256 amount) internal {
        vm.startPrank(user);
        weth.approve(address(debtManager), amount);
        debtManager.depositCollateralERC20(address(weth), amount);
        vm.stopPrank();
    }

}