// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MockAaveV3Pool } from "../test/mocks/MockAaveV3Pool.sol";
import { MockAaveOracle } from "../test/mocks/MockAaveOracle.sol";
import { MockPoolDataProvider } from "../test/mocks/MockPoolDataProvider.sol";
import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import "forge-std/console2.sol";
import { IPool } from "../src/interfaces/aave-v3/IPool.sol";

contract DeployAndConfigureMocks is Script {

    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant USDC_DECIMALS = 6;
    uint256 public constant WETH_USD_PRICE = 2000e8;
    uint256 public constant USDC_USD_PRICE = 1e8;
    uint256 public constant INITIAL_USDC_BALANCE = 100_000e6;
    uint256 public constant INITIAL_WETH_BALANCE = 100_000e18;

    MockERC20 public weth;
    MockERC20 public aWeth; // aToken
    MockERC20 public usdc;
    MockERC20 public aUsdc; // aToken
    MockERC20 public vUsdc; // vToken
    MockAaveV3Pool public mockPool;
    MockAaveOracle public oracle;
    MockPoolDataProvider public dataProvider;

    uint256 public deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    function run() external {

        vm.startBroadcast(deployerKey);

        // Deploy and configure mocks
        _createMockConfigs();

        vm.stopBroadcast();
    }

    function _createMockConfigs() internal {
        //////////// DEPLOY MOCK TOKENS //////////

        // WETH
        weth = new MockERC20("Wrapped ETH", "WETH", WETH_DECIMALS);
        // aWETH
        aWeth = new MockERC20("Aave WETH", "aWETH", 18);
        // USDC
        usdc = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        // aUSDC
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        // vUSDC
        vUsdc = new MockERC20("Variable Debt USDC", "vUSDC", 6);

        //////////// DEPLOY AND CONFIGURE MOCK AAVE POOL /////////////

        // Pool
        mockPool = new MockAaveV3Pool();

        // Setup reserve data in pool
        IPool.ReserveData memory reserveData_usdc = IPool.ReserveData({
            configuration: IPool.ReserveConfigurationMap(0),
            liquidityIndex: 1e27,
            currentLiquidityRate: 3e25,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 5e25,
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

        mockPool.setReserveData(address(usdc), reserveData_usdc);
        mockPool.setReserveData(address(weth), reserveData_weth);

        //////////////// DEPLOY AND CONFIGURE ORACLE //////////////

        // Oracle
        oracle = new MockAaveOracle();
        // Set prices
        oracle.setAssetPrice(address(weth), WETH_USD_PRICE);
        oracle.setAssetPrice(address(usdc), USDC_USD_PRICE);

        /////////////// DEPLOY AND CONFIGURE DATA PROVIDER //////////////

        // Data Provider
        dataProvider = new MockPoolDataProvider();

        // Setup reserve configuration data in PoolDataProvider
        MockPoolDataProvider.ReserveConfig memory reserveConfig_weth = MockPoolDataProvider.ReserveConfig({
            decimals: 1e18,
            ltv: 8000, // 80%
            liquidationThreshold: 8250, // 82.5%
            liquidationBonus: 10500, // 105%
            reserveFactor: 1000, // 10%
            usageAsCollateralEnabled: true,
            borrowingEnabled: true,
            stableBorrowRateEnabled: true,
            isActive: true,
            isFrozen: false
        });
        dataProvider.setReserveConfigurationData(address(weth), reserveConfig_weth);

        /////////////// FUND POOL WITH LIQUIDITY //////////////

        weth.mint(address(mockPool), INITIAL_WETH_BALANCE);
        aWeth.mint(address(mockPool), INITIAL_WETH_BALANCE);
        usdc.mint(address(mockPool), INITIAL_USDC_BALANCE);
        aUsdc.mint(address(mockPool), INITIAL_USDC_BALANCE);
        vUsdc.mint(address(mockPool), INITIAL_USDC_BALANCE);

        /////////////////////// LOGS //////////////////////

        console2.log("Deployed WETH at:", address(weth));
        console2.log("Deployed USDC at:", address(usdc));
        console2.log("Deployed MockAaveV3Pool at:", address(mockPool));
        console2.log("Deployed MockAaveOracle at:", address(oracle));
        console2.log("Deployed MockPoolDataProvider at:", address(dataProvider));

    }
}
