// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Health status of a user's account
enum HealthStatus {
    Liquidatable,   // < 1
    Danger,         // <= 1.1
    Healthy         // > 1.1
}

// User collateral type and amount
struct UserCollateral {
    string token;
    uint256 amount;
}

// Token type and amount earned from liquidation
struct LiquidationEarnings {
    string token;
    uint256 amount;
}