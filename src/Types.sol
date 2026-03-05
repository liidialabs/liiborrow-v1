// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Types
 * @author Liidia Team
 * @notice Defines custom types used throughout the LiiBorrow protocol.
 */

/**
 * @notice Represents the health status of a user's CDP position.
 * @dev Health is determined based on the health factor (HF):
 *      - Liquidatable: HF < 1.0 (user can be liquidated)
 *      - Danger: 1.0 <= HF <= 1.1 (at risk but not yet liquidatable)
 *      - Healthy: HF > 1.1 (position is safe)
 */
enum HealthStatus {
    Liquidatable, // HF < 1.0
    Danger,        // 1.0 <= HF <= 1.1
    Healthy       // HF > 1.1
}

/**
 * @notice Represents a user's supplied collateral position for a single token.
 * @dev Used to return collateral information in view functions.
 * @dev All values are in raw token units (not normalized to wad).
 */
struct UserCollateral {
    string symbol;    // Token symbol (e.g., "WETH", "WBTC")
    address collateral; // Token address
    uint256 amount;   // Amount of tokens supplied
    uint256 value;    // USD value of the amount (1e18 = 1 USD)
}

/**
 * @notice Represents earnings accrued through liquidation operations.
 * @dev Used to return liquidation revenue information.
 * @dev Amount is in raw token units for the respective collateral.
 */
struct LiquidationEarnings {
    string token;  // Token symbol (e.g., "WETH")
    uint256 amount; // Amount of tokens earned
}