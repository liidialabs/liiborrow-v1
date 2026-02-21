// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MockAavePool } from "../test/mocks/MockAavePool.sol";
import { MockAaveOracle } from "../test/mocks/MockAaveOracle.sol";
import { MockPoolDataProvider } from "../test/mocks/MockPoolDataProvider.sol";
import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import "forge-std/console2.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 public constant FEED_DECIMALS = 8;
    uint8 public constant WETH_DECIMALS = 18;
    uint8 public constant WBTC_DECIMALS = 8;
    uint8 public constant USDC_DECIMALS = 6;
    uint256 public constant ETH_USD_PRICE = 2000e8;
    uint256 public constant BTC_USD_PRICE = 40000e8;
    uint256 public constant USDC_USD_PRICE = 1e8;

    struct NetworkConfig {
        address cbeth;
        address cbbtc;
        address weth;
        address wbtc;
        address usdc;
        address pool;
        address oracle;
        address dataProvider;
        uint256 deployerKey;
    }

    MockERC20 public cbeth;
    MockERC20 public cbbtc;
    MockERC20 public weth;
    MockERC20 public wbtc;
    MockERC20 public usdc;
    MockAavePool public pool;
    MockAaveOracle public oracle;
    MockPoolDataProvider public dataProvider;

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        console2.log("Chain ID:", block.chainid);
        
        if (block.chainid == 111_55_111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 8453) {
            activeNetworkConfig = getBaseMainConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseMainConfig() public view returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            cbeth: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
            cbbtc: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,
            weth: 0x4200000000000000000000000000000000000006,
            wbtc: address(0),
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            pool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5,
            oracle: 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156,
            dataProvider: address(123456789), // TODO: replace with actual data provider address
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            cbeth: address(0),
            cbbtc: address(0),
            weth: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c,
            wbtc: 0x29f2D40B0605204364af54EC677bD022dA425d03,
            usdc: 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,
            pool: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951,
            oracle: 0x2da88497588bf89281816106C7259e31AF45a663,
            dataProvider: 0x3e9708d80f7B3e43118013075F7e95CE3AB31F31,
            deployerKey: vm.envUint("PRIVATE_KEY_DEPLOYER")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.pool != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        // CBETH
        cbeth = new MockERC20("Coinbase ETH", "CBETH", WETH_DECIMALS);
        // CBBTC
        cbbtc = new MockERC20("Coinbase BTC", "CBBTC", WBTC_DECIMALS);
        // WETH
        weth = new MockERC20("Wrapped ETH", "WETH", WETH_DECIMALS);
        // WBTC
        wbtc = new MockERC20("Wrapped BTC", "WBTC", WBTC_DECIMALS);
        // USDC
        usdc = new MockERC20("USD Coin", "USDC", USDC_DECIMALS);
        // Pool
        pool = new MockAavePool();
        // Oracle
        oracle = new MockAaveOracle();
        // Set prices
        oracle.setAssetPrice(address(cbeth), ETH_USD_PRICE);
        oracle.setAssetPrice(address(cbbtc), BTC_USD_PRICE);
        oracle.setAssetPrice(address(weth), ETH_USD_PRICE);
        oracle.setAssetPrice(address(wbtc), BTC_USD_PRICE);
        oracle.setAssetPrice(address(usdc), USDC_USD_PRICE);
        vm.stopBroadcast();
        // Data Provider
        dataProvider = new MockPoolDataProvider();

        anvilNetworkConfig = NetworkConfig({
            cbeth: address(cbeth),
            cbbtc: address(cbbtc),
            weth: address(weth),
            wbtc: address(wbtc),
            usdc: address(usdc),
            pool: address(pool),
            oracle: address(oracle),
            dataProvider: address(dataProvider),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
