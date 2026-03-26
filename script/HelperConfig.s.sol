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
        address usdt;
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
        if (block.chainid == 1) { // Can simulate mainnet with Tenderly Virtual TestNet
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
            cbeth: address(0),
            cbbtc: address(0),
            weth: 0x49C954F846e870FE5402C7F65cD035592c81aadB,
            wbtc: address(0),
            usdc: 0x8ca959E4c4745df0E2fE5CE5fAcFD3F35ae509e9,
            usdt: 0xCF146342D638FE3Ac96A9A6E61Eb2F2Ee38221c9,
            pool: 0xd64033432e085905487A490441C0cF8D47E1c40f,
            oracle: 0xDFe8c6121b43e3B5bd0731F724007D0119B838bc,
            dataProvider: 0x7F3e4036e201a35b147574554DBE698940E2758D,
            deployerKey: deployerKey
        });
        mainnetCoreConfig = CoreConfig({
            debtManagerAddress: 0x4E0Af3287669D331BB5B858B738B0be069b7C750,
            aaveAddress: 0x4fc08467e75db0123480d869239Afd9CCBeE0951
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
            usdt: address(0),
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
