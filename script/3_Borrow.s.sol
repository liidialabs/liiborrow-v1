// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { HealthStatus } from "../src/Types.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

/// @notice This script supplies ETH to the protocol
contract Borrow is Script {
    DebtManager private debtManager;
    Aave private aave;
    HelperConfig private helperConfig;
    
    uint256 private borrowAmount = 1200e6;
    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        (
            ,, address weth,,,,,,
        ) = helperConfig.activeNetworkConfig();
        (
            address debtManagerAddress,
        ) = helperConfig.activeCoreConfig();

        // Initialize the DebtManager contract
        debtManager = DebtManager(payable(debtManagerAddress));

        vm.startBroadcast(USER); 

        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(USER));
        (uint256 aaveDebtBefore, ) = debtManager.getUserDebt(vm.addr(USER));
        uint256 balance = debtManager.getCollateralBalanceOfUser(vm.addr(USER), weth);
        console2.log("User collateral balance from DebtManager: %s WETH", balance);
        console2.log("User Health Factor before borrow: %s", hfBefore);
        console2.log("User Debt before borrow: %s USDC", aaveDebtBefore);
        console2.log("------------------------------------------------------------");

        // Borrow USDC
        debtManager.borrowUsdc(borrowAmount);

        vm.stopBroadcast();

        uint256 hfAfter = debtManager.getHealthFactor(vm.addr(USER));
        (uint256 aaveDebtAfter, ) = debtManager.getUserDebt(vm.addr(USER));
        bool isLiquid = debtManager.isLiquidatable(vm.addr(USER));
        console2.log("------------------------------------------------------------");
        console2.log("User Debt after borrow: %s USDC", aaveDebtAfter / 1e6);
        console2.log("User Health Factor after borrow: %s", hfAfter);
        console2.log("User is liquidatable after borrow: %s", isLiquid);

    }
}

