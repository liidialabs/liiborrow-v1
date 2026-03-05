// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

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

    address public constant debtManagerAddress = 0xFB56BcBB16eF411Ad25EE507d7c2430e561ae3E0;
    address public constant aaveAddress = 0x4051A4D767C41074bA8d714083DB2308EA55B7c4;
    uint256 deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    constructor() {        
        if (block.chainid == 111_55_111) {
            // activeNetworkConfig = getSepoliaEthConfig();
            activeNetworkConfig = getMockConfigs();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseMainConfig();
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
            deployerKey: deployerKey
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
            deployerKey: deployerKey
        });
    }

    function getMockConfigs() public view returns (NetworkConfig memory createdNetworkConfig) { 
        createdNetworkConfig = NetworkConfig({
            cbeth: address(0),
            cbbtc: address(0),
            weth: 0x6de4964bfEbCa1848c74FeaA6736b14898DfDB0c,
            wbtc: address(0),
            usdc: 0x23256311E41354c00E880D5b923A64552f077FD3,
            pool: 0xe1B210f9064001a2db724e8DA6166CD76737DD40,
            oracle: 0xe6dC6561a06cFD9969761913D38EcC58cE7227B9,
            dataProvider: 0x257b85Bf832B8C87Db948e37A00C1f61d2F15743,
            deployerKey: deployerKey
        });
    }
}
