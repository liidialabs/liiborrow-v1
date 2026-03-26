// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { UserCollateral, HealthStatus } from "../src/Types.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { MockAaveV3Pool } from "../test/mocks/MockAaveV3Pool.sol";

/// @notice This script supplies ETH to the protocol
contract Supply is Script {
    DebtManager private debtManager;
    Aave private aave;
    HelperConfig private helperConfig;
    MockERC20 private WETH;
    MockAaveV3Pool private mockPool;

    address private user; 
    
    uint256 private supplyAmount = 1 ether;
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        (
            ,, address weth,,,, address _pool,,,
        ) = helperConfig.activeNetworkConfig();
        (
            address debtManagerAddress,
            address aaveAddress
        ) = helperConfig.activeCoreConfig();

        // user wallet
        user = vm.addr(userKey);

        // create contract instances
        debtManager = DebtManager(payable(debtManagerAddress));
        aave = Aave(aaveAddress);
        WETH = MockERC20(weth);
        mockPool = MockAaveV3Pool(_pool);

        vm.startBroadcast(userKey);

        // mint WETH
        WETH.mint(user, supplyAmount);
        // approve WETH to be spent by debt manager
        WETH.approve(address(debtManager), supplyAmount);
        // supply WETH to the protocol
        debtManager.depositCollateralERC20(weth, supplyAmount, user);

        vm.stopBroadcast();

        console2.log("Successfully supplied WETH to the protocol!");

        // Get and log user's supplied collateral after supplying
        UserCollateral[] memory userCollateral = debtManager
            .getUserSuppliedCollateralAmount(user);
        
        console2.log("User's supplied collateral after supplying:");
        for (uint256 i = 0; i < userCollateral.length; i++) {
            console2.log("Symbol:", userCollateral[i].symbol);
            console2.log("Collateral:", userCollateral[i].collateral);
            console2.log("Amount:", userCollateral[i].amount / 1e18);
            console2.log("Value:", userCollateral[i].value / 1e18);
        }
    }
}
