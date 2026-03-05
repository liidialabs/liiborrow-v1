// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { Aave } from  "../src/Aave.sol";
import { HealthStatus, UserCollateral } from "../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

/// @notice This script withdraws debt in the protocol
contract Withdraw is Script {
    DebtManager private debtManager;
    Aave private aave;
    HelperConfig private helperConfig;
    
    uint256 private withdrawAmount = 0.05 ether;
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        // Get token, pool & oracle addresses from the active network config
        (
            ,,
            address weth,
            ,,,,,
        ) = helperConfig.activeNetworkConfig();
        (
            address debtManagerAddress,
            address aaveAddress
        ) = helperConfig.activeCoreConfig();

        // Initialize the DebtManager & Aave contract
        debtManager = DebtManager(payable(debtManagerAddress));
        aave = Aave(aaveAddress);

        address USER = vm.addr(userKey);

        // Log protocol's supply balance in WETH after supplying
        uint256 supplyBalance = aave.getSupplyBalance(debtManagerAddress, weth);
        console2.log("Protocol's supply balance before in WETH:", supplyBalance);

        // Get and log user's supplied collateral after supplying
        UserCollateral[] memory userCollateral = debtManager
            .getUserSuppliedCollateralAmount(USER);
        
        console2.log("User's supplied collateral before supplying:");
        for (uint256 i = 0; i < userCollateral.length; i++) {
            console2.log("Symbol:", userCollateral[i].symbol);
            console2.log("Collateral:", userCollateral[i].collateral);
            console2.log("Amount:", userCollateral[i].amount);
            console2.log("Value:", userCollateral[i].value);
        }
        console2.log("------------");
        (uint256 userAaveDebt,) = debtManager.getUserDebt(USER);
        console2.log("User Aave debt:", userAaveDebt);

        vm.startBroadcast(userKey);

        // withdraw Weth from debt
        debtManager.redeemCollateral(weth, withdrawAmount, false);

        vm.stopBroadcast();

        console2.log("-----------------------------------------");
        console2.log("Successfully withdrew collateral supplied");
        console2.log("-----------------------------------------");

        // Log protocol's supply balance in WETH after supplying
        supplyBalance = aave.getSupplyBalance(debtManagerAddress, weth);
        console2.log("Protocol's supply balance after in WETH:", supplyBalance);

        // Get and log user's supplied collateral after supplying
        userCollateral = debtManager.getUserSuppliedCollateralAmount(USER);
        
        console2.log("User's supplied collateral after supplying:");
        for (uint256 i = 0; i < userCollateral.length; i++) {
            console2.log("Symbol:", userCollateral[i].symbol);
            console2.log("Collateral:", userCollateral[i].collateral);
            console2.log("Amount:", userCollateral[i].amount);
            console2.log("Value:", userCollateral[i].value);
        }
    
    }
}
