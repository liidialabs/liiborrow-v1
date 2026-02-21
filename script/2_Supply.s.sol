// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { UserCollateral, HealthStatus } from "../src/Types.sol";

/// @notice This script supplies ETH to the protocol
contract Supply is Script {
    DebtManager private debtManager;
    Aave private aave;

    address private DebtManagerAddress = 0x7EDcd4EC208E536e05aBE97213B54cb77E8007ce;
    address private aaveAddress = 0x555d05ccf5590068679c07519445705f9f8CB62f;
    address private WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c; 
    address private user = 0xC099f8A2C5117C81652A506aFfE10a6E77e79808; 
    
    uint256 private supplyAmount = 0.1 ether;
    uint256 private deployerKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Initialize the DebtManager & Aave contract
        debtManager = DebtManager(payable(DebtManagerAddress));
        aave = Aave(aaveAddress);

        vm.startBroadcast(deployerKey);

        // supply ETH to the protocol
        debtManager.depositCollateralETH{value: supplyAmount}(supplyAmount);

        vm.stopBroadcast();

        console2.log("Successfully supplied ETH to the protocol!");

        // Get and log user's supplied collateral after supplying
        UserCollateral[] memory userCollateral = debtManager
            .getUserSuppliedCollateralAmount(user);
        
        console2.log("User's supplied collateral after supplying:");
        for (uint256 i = 0; i < userCollateral.length; i++) {
            console2.log("Symbol:", userCollateral[i].symbol);
            console2.log("Collateral:", userCollateral[i].collateral);
            console2.log("Amount:", userCollateral[i].amount);
            console2.log("Value:", userCollateral[i].value);
        }

        // Log protocol's Aave position
        (
            uint256 collateralUSD,
            uint256 debtUSD,
            uint256 canBorrowUSD,
            uint256 canBorrowUSDC,
            uint256 _currentLiquidationThreshold,
            uint256 _ltv
        ) = aave.getUserAccountData(DebtManagerAddress);

        console2.log("Protocol's Aave position after supplying:");
        console2.log("Collateral in USD:", collateralUSD);
        console2.log("Debt in USD:", debtUSD);
        console2.log("Available to borrow in USD:", canBorrowUSD);
        console2.log("Available to borrow in USDC:", canBorrowUSDC);
        console2.log("Current Liquidation Threshold:", _currentLiquidationThreshold);
        console2.log("Loan to Value ratio:", _ltv);

        // Log protocol's health factor after supplying
        (uint256 hf, HealthStatus status) = aave.getHealthFactor(DebtManagerAddress);
        console2.log("Protocol's health factor after supplying:", hf);
        console2.log("Protocol's health status after supplying:", uint256(status));

        // Log protocol's supply balance in WETH after supplying
        uint256 supplyBalance = aave.getSupplyBalance(DebtManagerAddress, WETH);
        console2.log("Protocol's supply balance in WETH:", supplyBalance);
    }
}
