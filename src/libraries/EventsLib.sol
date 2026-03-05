// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EventsLib
 * @author Liidia Team
 * @notice Library containing event definitions for the LiiBorrow protocol.
 * @dev Events are emitted by DebtManager to track protocol operations on-chain.
 */
library EventsLib {
    // DebtManager Events

    /// @notice Emitted when a user deposits collateral into the protocol.
    /// @param user The account that deposited collateral.
    /// @param token The collateral token address (ERC20 or ETH sentinel address(0)).
    /// @param amount The amount of collateral deposited (in raw token units).
    event Supply(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a user redeems collateral from the protocol.
    /// @param redeemFrom The account whose collateral was redeemed.
    /// @param redeemTo The recipient of the redeemed collateral.
    /// @param token The collateral token address.
    /// @param amount The amount of collateral redeemed (in raw token units).
    event Withdraw(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when a user is liquidated by a liquidator.
    /// @param by The address of the liquidator.
    /// @param from The address of the user being liquidated.
    /// @param token The collateral token address that was seized.
    /// @param amount The amount of collateral seized.
    /// @param timestamp The block timestamp when the liquidation occurred.
    event Liquidated(
        address indexed by,
        address indexed from,
        address indexed token,
        uint256 amount,
        uint32 timestamp
    );

    /// @notice Emitted when a user borrows USDC from the protocol.
    /// @param user The borrower's address.
    /// @param amount The amount of USDC borrowed (in USDC units).
    /// @param timestamp The block timestamp when the borrow occurred.
    event Borrow(address indexed user, uint256 amount, uint32 timestamp);

    /// @notice Emitted when a user repays USDC debt to the protocol.
    /// @param user The repayer's address.
    /// @param amount The amount of USDC repaid (in USDC units).
    /// @param timestamp The block timestamp when the repayment occurred.
    event RepayUsdc(address indexed user, uint256 amount, uint32 timestamp);

    /// @notice Emitted when protocol revenue is withdrawn by the owner.
    /// @param to The recipient address (e.g., treasury).
    /// @param asset The asset address being withdrawn.
    /// @param amount The amount withdrawn (in raw token units).
    /// @param timestamp The block timestamp when the withdrawal occurred.
    event RevenueWithdrawn(
        address indexed to,
        address indexed asset,
        uint256 amount,
        uint32 timestamp
    );

    // Aave Events
}
