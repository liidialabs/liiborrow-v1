// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPool } from "../../src/interfaces/aave-v3/IPool.sol";
import { MockERC20 } from "./MockERC20.sol";

/**
 * @title MockPool
 * @notice Mock implementation of Aave V3 Pool for testing
 * @dev Simulates key Pool functions with configurable behavior for testing
 */
 
contract MockAavePool is IPool {

    // Control flags for testing
    bool public shouldRevertOnSupply;
    bool public shouldRevertOnWithdraw;
    bool public shouldRevertOnBorrow;
    bool public shouldRevertOnRepay;
    bool public shouldRevertOnLiquidation;
    
    uint256 public flashLoanFee = 9; // 0.09% (9 basis points)

    struct UserAccountData {
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowsBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }
    
    // State variables for testing
    mapping(address => ReserveData) private reserves;
    mapping(address => UserAccountData) private userAccounts;
    mapping(address => mapping(address => uint256)) public userCollateral; // user => asset => amount
    mapping(address => mapping(address => uint256)) public userDebt; // user => asset => amount
    
    // Mock aToken addresses
    mapping(address => address) public assetToAToken;
    
    // Events for testing
    event MockSupply(address indexed asset, uint256 amount, address indexed onBehalfOf);
    event MockWithdraw(address indexed asset, uint256 amount, address indexed to);
    event MockBorrow(address indexed asset, uint256 amount, address indexed onBehalfOf);
    event MockRepay(address indexed asset, uint256 amount, address indexed onBehalfOf);
    event MockLiquidation(address indexed collateral, address indexed debt, address indexed user, uint256 debtToCover);
    event MockFlashLoan(address indexed receiver, address indexed asset, uint256 amount);
    
    constructor() {}
    
    // ============ SETUP FUNCTIONS FOR TESTING ============
    
    /**
     * @notice Set mock user account data for testing
     */
    function setUserAccountData(
        address user,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) external {
        userAccounts[user] = UserAccountData({
            totalCollateralBase: totalCollateralBase,
            totalDebtBase: totalDebtBase,
            availableBorrowsBase: availableBorrowsBase,
            currentLiquidationThreshold: currentLiquidationThreshold,
            ltv: ltv,
            healthFactor: healthFactor
        });
    }
    
    /**
     * @notice Set reserve data for an asset
     */
    function setReserveData(address asset, ReserveData memory data) external {
        reserves[asset] = data;
    }
    
    /**
     * @notice Set aToken address for an asset
     */
    function setATokenAddress(address asset, address aToken) external {
        assetToAToken[asset] = aToken;
        reserves[asset].aTokenAddress = aToken;
    }
    
    /**
     * @notice Set collateral for a user
     */
    function setUserCollateral(address user, address asset, uint256 amount) external {
        userCollateral[user][asset] = amount;
    }
    
    /**
     * @notice Set debt for a user
     */
    function setUserDebt(address user, address asset, uint256 amount) external {
        userDebt[user][asset] = amount;
    }
    
    // ============ REVERT CONTROL FOR TESTING ============
    
    function setShouldRevertOnSupply(bool _shouldRevert) external {
        shouldRevertOnSupply = _shouldRevert;
    }
    
    function setShouldRevertOnWithdraw(bool _shouldRevert) external {
        shouldRevertOnWithdraw = _shouldRevert;
    }
    
    function setShouldRevertOnBorrow(bool _shouldRevert) external {
        shouldRevertOnBorrow = _shouldRevert;
    }
    
    function setShouldRevertOnRepay(bool _shouldRevert) external {
        shouldRevertOnRepay = _shouldRevert;
    }
    
    function setShouldRevertOnLiquidation(bool _shouldRevert) external {
        shouldRevertOnLiquidation = _shouldRevert;
    }
    
    function setFlashLoanFee(uint256 _fee) external {
        flashLoanFee = _fee;
    }
    
    // ============ POOL INTERFACE IMPLEMENTATION ============
    
    /**
     * @notice Supply assets to the pool
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        require(!shouldRevertOnSupply, "MockPool: supply reverted");
        
        // Transfer tokens from sender to pool
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(reserves[asset].aTokenAddress).transfer(onBehalfOf, amount);
        
        // Update user collateral
        userCollateral[onBehalfOf][asset] += amount;
        
        emit MockSupply(asset, amount, onBehalfOf);
    }
    
    /**
     * @notice Withdraw assets from the pool
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        require(!shouldRevertOnWithdraw, "MockPool: withdraw reverted");
        require(userCollateral[msg.sender][asset] >= amount, "MockPool: insufficient collateral");
        require(
            IERC20(reserves[asset].aTokenAddress).balanceOf(to) >= amount,
            "Insufficient aToken"
        );

        // burn aTokens
        MockERC20(reserves[asset].aTokenAddress).burn(to, amount);
        
        // Update user collateral
        userCollateral[msg.sender][asset] -= amount;
        
        // Transfer tokens to recipient
        IERC20(asset).transfer(to, amount);
        
        emit MockWithdraw(asset, amount, to);
        return amount;
    }
    
    /**
     * @notice Borrow assets from the pool
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external override {
        require(!shouldRevertOnBorrow, "MockPool: borrow reverted");
        
        // Update user debt
        userDebt[onBehalfOf][asset] += amount;
        
        // Transfer borrowed tokens to user
        IERC20(asset).transfer(msg.sender, amount);

        // 'Mint' vUsdc
        IERC20(reserves[asset].variableDebtTokenAddress).transfer(onBehalfOf, amount);
        
        emit MockBorrow(asset, amount, onBehalfOf);
    }
    
    /**
     * @notice Repay borrowed assets
     */
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external override returns (uint256) {
        require(!shouldRevertOnRepay, "MockPool: repay reverted");
        require(
            IERC20(reserves[asset].variableDebtTokenAddress).balanceOf(onBehalfOf) >= amount,
            "Insufficient vToken"
        );
        
        uint256 debtAmount = userDebt[onBehalfOf][asset];
        uint256 amountToRepay = amount > debtAmount ? debtAmount : amount;
        
        // burn variable tokens
        MockERC20(reserves[asset].variableDebtTokenAddress).burn(onBehalfOf, amount);
        // Transfer tokens from sender to pool
        IERC20(asset).transferFrom(msg.sender, address(this), amountToRepay);
        
        // Update user debt
        userDebt[onBehalfOf][asset] -= amountToRepay;
        
        emit MockRepay(asset, amountToRepay, onBehalfOf);
        return userDebt[onBehalfOf][asset];
    }
    
    /**
     * @notice Liquidate undercollateralized position
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external override {
        require(!shouldRevertOnLiquidation, "MockPool: liquidation reverted");
        
        // Transfer debt payment from liquidator
        IERC20(debtAsset).transferFrom(msg.sender, address(this), debtToCover);
        
        // Calculate collateral to seize (simplified: 1:1 ratio for testing)
        uint256 collateralToSeize = debtToCover;
        
        // Update user debt and collateral
        userDebt[user][debtAsset] -= debtToCover;
        userCollateral[user][collateralAsset] -= collateralToSeize;
        
        // Transfer collateral to liquidator
        if (!receiveAToken) {
            IERC20(collateralAsset).transfer(msg.sender, collateralToSeize);
        }
        
        emit MockLiquidation(collateralAsset, debtAsset, user, debtToCover);
    }
    
    /**
     * @notice Flash loan
     */
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external override {
        uint256 premium = (amount * flashLoanFee) / 10000;
        uint256 amountPlusPremium = amount + premium;
        
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        
        // Transfer flash loan amount to receiver
        IERC20(asset).transfer(receiverAddress, amount);
        
        // Execute receiver logic (simplified - in real Aave, calls executeOperation)
        // For testing, we just expect the receiver to return the funds
        
        // Verify repayment
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + premium, "MockPool: flash loan not repaid");
        
        emit MockFlashLoan(receiverAddress, asset, amount);
    }
    
    /**
     * @notice Get user account data
     */
    function getUserAccountData(address user)
        external
        view
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        UserAccountData memory data = userAccounts[user];
        return (
            data.totalCollateralBase,
            data.totalDebtBase,
            data.availableBorrowsBase,
            data.currentLiquidationThreshold,
            data.ltv,
            data.healthFactor
        );
    }
    
    /**
     * @notice Get reserve data for an asset
     */
    function getReserveData(address asset)
        external
        view
        override
        returns (ReserveData memory)
    {
        return reserves[asset];
    }
    
    // ============ HELPER FUNCTIONS ============
    
    /**
     * @notice Get user's collateral balance
     */
    function getUserCollateral(address user, address asset) external view returns (uint256) {
        return userCollateral[user][asset];
    }
    
    /**
     * @notice Get user's debt balance
     */
    function getUserDebt(address user, address asset) external view returns (uint256) {
        return userDebt[user][asset];
    }
    
    /**
     * @notice Fund the mock pool with tokens for testing
     */
    function fundPool(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }
}