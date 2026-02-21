// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { HealthStatus } from "../src/Types.sol";

/// @notice This script supplies ETH to the protocol
contract Borrow is Script {
    DebtManager private debtManager;
    Aave private aave;

    address private DebtManagerAddress = 0x7EDcd4EC208E536e05aBE97213B54cb77E8007ce;
    address private aaveAddress = 0x555d05ccf5590068679c07519445705f9f8CB62f;
    address private USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; 
    address private user = 0xC099f8A2C5117C81652A506aFfE10a6E77e79808;
    
    uint256 private borrowAmount = 100e6;
    uint256 private deployerKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Initialize the DebtManager contract
        debtManager = DebtManager(payable(DebtManagerAddress));
        aave = Aave(aaveAddress);

        vm.startBroadcast(deployerKey);

        // Borrow USDC
        debtManager.borrowUsdc(borrowAmount);

        vm.stopBroadcast();

        console2.log("Successfully borrowed USDC from the protocol!");

        // Get and log user's debt after borrowing
        (uint256 aaveDebt, uint256 allDebt) = debtManager.getUserDebt(user);
        uint256 userShares = debtManager.getUserShares(user);
        uint256 hf = debtManager.getHealthFactor(user);
        console2.log("User's Aave debt after borrowing:", aaveDebt);
        console2.log("User's all debt after borrowing:", allDebt);
        console2.log("User's shares after borrowing:", userShares);
        console2.log("User's health factor after borrowing:", hf);

        // Get and log total variable debt and shares of the protocol after borrowing
        uint256 balance = aave.getVariableDebt(DebtManagerAddress, USDC);
        uint256 shares = debtManager.getTotalDebtShares();
        console2.log("Total variable debt of the protocol after borrowing:", balance);
        console2.log("Total debt shares of the protocol after borrowing:", shares);

        // Log protocol's health factor after borrowing
        (uint256 protocolHf, HealthStatus protocolStatus) = aave.getHealthFactor(DebtManagerAddress);
        console2.log("Protocol's health factor after borrowing:", protocolHf);
        console2.log("Protocol's health status after borrowing:", uint256(protocolStatus));

        // Log protocol's account data after borrowing
        (
            uint256 collateralUSD,
            uint256 debtUSD,
            uint256 canBorrowUSD,
            uint256 canBorrowUSDC,
            uint256 _currentLiquidationThreshold,
            uint256 _ltv
        ) = aave.getUserAccountData(DebtManagerAddress);
        console2.log("Protocol's account data after borrowing:");
        console2.log("Collateral in USD:", collateralUSD);
        console2.log("Debt in USD:", debtUSD);
        console2.log("Available to borrow in USD:", canBorrowUSD);
        console2.log("Available to borrow in USDC:", canBorrowUSDC);
        console2.log("Current Liquidation Threshold:", _currentLiquidationThreshold);
        console2.log("Loan to Value ratio:", _ltv);

    }
}

