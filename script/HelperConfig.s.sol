// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

/// @title HelperConfig
/// @author Liidia Team
/// @notice This contract manages network configurations for different blockchain networks
/// @dev Automatically selects the appropriate network config based on the current chain ID
contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;
    CoreConfig public activeCoreConfig;

    /// @notice Configuration for network-specific addresses and parameters
    /// @dev Contains all the protocol and token addresses for a given network
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

    /// @notice Configuration for core protocol addresses
    /// @dev Contains addresses for debt manager and aave protocol
    struct CoreConfig {
        address debtManagerAddress;
        address aaveAddress;
    }

    /// @notice The deployer private key from environment variables
    uint256 deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    /// @notice Constructor that sets up the active network configuration
    /// @dev Automatically detects chain ID and loads appropriate config
    constructor() {
        if (block.chainid == 111_55_111) {
            (activeNetworkConfig, activeCoreConfig) = getSepoliaConfig();
        }
        if (block.chainid == 1) {
            (activeNetworkConfig, activeCoreConfig) = getMainnetConfig();
        }
    }

    function getMainnetConfig()
        public
        view
        returns (
            NetworkConfig memory mainnetNetworkConfig,
            CoreConfig memory mainnetCoreConfig
        )
    {
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
        mainnetCoreConfig = CoreConfig({
            debtManagerAddress: address(0),
            aaveAddress: address(0)
        });
    }

    function getSepoliaConfig()
        public
        view
        returns (
            NetworkConfig memory sepoliaNetworkConfig,
            CoreConfig memory sepoliaCoreConfig
        )
    {
        sepoliaNetworkConfig = NetworkConfig({
            cbeth: address(0),
            cbbtc: address(0),
            weth: address(0),
            wbtc: address(0),
            usdc: address(0),
            pool: address(0),
            oracle: address(0),
            dataProvider: address(0),
            deployerKey: deployerKey
        });
        sepoliaCoreConfig = CoreConfig({
            debtManagerAddress: address(0),
            aaveAddress: address(0)
        });
    }
}
