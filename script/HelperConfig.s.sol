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

    address public constant debtManagerAddress = 0x3f26685991D09eCd40227Efb7649Ca2A371708CC;
    address public constant aaveAddress = 0x2853eA59358977011a8Bf653ab00d975871e3D6e;

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

    function getMockConfigs() public view returns (NetworkConfig memory createdNetworkConfig) { 
        createdNetworkConfig = NetworkConfig({
            cbeth: address(0),
            cbbtc: address(0),
            weth: 0x394A1145Cc4480cD047ad065a5Ece23D4fcC2E1d,
            wbtc: address(0),
            usdc: 0xf8340a3BB21282Af32B567e0ACE1Cc5c4eF63a73,
            pool: 0xDB79AF69617bFcB71D55E7575bFbb1De86151eF9,
            oracle: 0x10C979d0f556799262CF3934e211BDA4e4E9074A,
            dataProvider: 0x939d6989D15CF96F6E1cE8b6067d016fbf0D7C67,
            deployerKey: vm.envUint("PRIVATE_KEY_DEPLOYER")
        });
    }
}
