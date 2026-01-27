// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPoolDataProvider } from "../../src/interfaces/aave-v3/IPoolDataProvider.sol";

/**
 * @title MockPoolDataProvider
 * @notice Mock implementation of Aave V3 PoolDataProvider for testing
 * @dev Simulates key PoolDataProvider functions with configurable behavior for testing
 */
 
contract MockPoolDataProvider is IPoolDataProvider {
    // Mocked reserve configuration data
    struct ReserveConfig {
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        bool usageAsCollateralEnabled;
        bool borrowingEnabled;
        bool stableBorrowRateEnabled;
        bool isActive;
        bool isFrozen;
    }

    mapping(address => ReserveConfig) private reserveConfigs;

    constructor() {}

    /**
     * @notice Sets the mock reserve configuration data for a given asset
     * @param asset The address of the asset
     * @param config The ReserveConfig struct containing the configuration data
     */
    function setReserveConfigurationData(address asset, ReserveConfig memory config) external {
        reserveConfigs[asset] = config;
    }

    /**
     * @notice Gets the reserve configuration data for a given asset
     * @param asset The address of the asset
     * @return decimals The number of decimals for the asset
     * @return ltv The loan-to-value ratio
     * @return liquidationThreshold The liquidation threshold
     * @return liquidationBonus The liquidation bonus
     * @return reserveFactor The reserve factor
     * @return usageAsCollateralEnabled Whether usage as collateral is enabled
     * @return borrowingEnabled Whether borrowing is enabled
     * @return stableBorrowRateEnabled Whether stable borrow rate is enabled
     * @return isActive Whether the reserve is active
     * @return isFrozen Whether the reserve is frozen
     */
    function getReserveConfigurationData(address asset)
        external
        view
        override
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        )
    {
        ReserveConfig memory config = reserveConfigs[asset];
        return (
            config.decimals,
            config.ltv,
            config.liquidationThreshold,
            config.liquidationBonus,
            config.reserveFactor,
            config.usageAsCollateralEnabled,
            config.borrowingEnabled,
            config.stableBorrowRateEnabled,
            config.isActive,
            config.isFrozen
        );
    }
}