// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library EventsLib {
    // DebtManager Events

    event Supply(address indexed user, address indexed token, uint256 amount);
    event Withdraw(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );
    event Liquidated(
        address indexed by,
        address indexed from,
        address indexed token,
        uint256 amount,
        uint32 timestamp
    );
    event Borrow(address indexed user, uint256 amount, uint32 timestamp);
    event RepayUsdc(address indexed user, uint256 amount, uint32 timestamp);
    event RevenueWithdrawn(
        address indexed to,
        address indexed asset,
        uint256 amount,
        uint32 timestamp
    );

    // Aave Events
}
