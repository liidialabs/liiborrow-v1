// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "../../src/interfaces/aave-v3/IPriceOracle.sol";

/**
 * @title MockAaveOracle
 * @notice Mock implementation of Aave Oracle for testing
 * @dev Returns configurable asset prices in USD (1 USD = 1e8)
 */

contract MockAaveOracle is IPriceOracle {
    // Mapping of asset address to price in USD (8 decimals)
    mapping(address => uint256) private assetPrices;

    // Default price if not set (e.g., $1 = 1e8)
    uint256 public defaultPrice = 1e8;

    // Control flag for testing
    bool public shouldRevert;

    // Events for testing
    event PriceUpdated(address indexed asset, uint256 price);
    event PriceRequested(address indexed asset, uint256 price);

    constructor() {}

    // ============ SETUP FUNCTIONS FOR TESTING ============

    /**
     * @notice Set price for a specific asset
     * @param asset The asset address
     * @param price The price in USD with 8 decimals (e.g., $2000 = 2000e8)
     */
    function setAssetPrice(address asset, uint256 price) external {
        assetPrices[asset] = price;
        emit PriceUpdated(asset, price);
    }

    /**
     * @notice Set prices for multiple assets at once
     * @param assets Array of asset addresses
     * @param prices Array of prices (must match assets length)
     */
    function setAssetPrices(
        address[] calldata assets,
        uint256[] calldata prices
    ) external {
        require(assets.length == prices.length, "MockOracle: length mismatch");

        for (uint256 i = 0; i < assets.length; i++) {
            assetPrices[assets[i]] = prices[i];
            emit PriceUpdated(assets[i], prices[i]);
        }
    }

    /**
     * @notice Set default price for assets without specific price
     * @param price The default price in USD with 8 decimals
     */
    function setDefaultPrice(uint256 price) external {
        defaultPrice = price;
    }

    /**
     * @notice Control whether the oracle should revert (for testing failures)
     * @param _shouldRevert True to make getAssetPrice revert
     */
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    // ============ ORACLE INTERFACE IMPLEMENTATION ============

    /**
     * @notice Get the price of an asset in USD
     * @param asset The asset address
     * @return price The price in USD with 8 decimals
     */
    function getAssetPrice(
        address asset
    ) external view override returns (uint256) {
        require(!shouldRevert, "MockOracle: reverted");

        uint256 price = assetPrices[asset];

        // Return specific price if set, otherwise return default
        return price != 0 ? price : defaultPrice;
    }

    // ============ HELPER FUNCTIONS ============

    /**
     * @notice Check if an asset has a specific price set
     * @param asset The asset address
     * @return bool True if asset has a specific price
     */
    function hasAssetPrice(address asset) external view returns (bool) {
        return assetPrices[asset] != 0;
    }

    /**
     * @notice Update price and emit event (useful for testing price changes)
     * @param asset The asset address
     * @param newPrice The new price
     */
    function updatePrice(address asset, uint256 newPrice) external {
        assetPrices[asset] = newPrice;
        emit PriceUpdated(asset, newPrice);
    }

    /**
     * @notice Simulate price crash for testing
     * @param asset The asset address
     * @param percentDrop Percentage to drop (e.g., 50 = 50% drop)
     */
    function simulatePriceCrash(address asset, uint256 percentDrop) external {
        require(percentDrop <= 100, "MockOracle: invalid percent");
        uint256 currentPrice = assetPrices[asset];
        require(currentPrice != 0, "MockOracle: price not set");

        uint256 newPrice = (currentPrice * (100 - percentDrop)) / 100;
        assetPrices[asset] = newPrice;
        emit PriceUpdated(asset, newPrice);
    }

    /**
     * @notice Simulate price pump for testing
     * @param asset The asset address
     * @param percentIncrease Percentage to increase (e.g., 50 = 50% increase)
     */
    function simulatePricePump(
        address asset,
        uint256 percentIncrease
    ) external {
        uint256 currentPrice = assetPrices[asset];
        require(currentPrice != 0, "MockOracle: price not set");

        uint256 newPrice = (currentPrice * (100 + percentIncrease)) / 100;
        assetPrices[asset] = newPrice;
        emit PriceUpdated(asset, newPrice);
    }

    /**
     * @notice Reset all prices (useful between tests)
     */
    function resetPrices() external {
        // Note: Can't easily clear mapping, so caller should track assets
        // or redeploy contract for clean state
        defaultPrice = 1e8;
        shouldRevert = false;
    }
}
