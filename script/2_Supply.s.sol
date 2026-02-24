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
    HelperConfig public helperConfig;
    MockERC20 public weth;
    MockAaveV3Pool public mockPool;

    address private user; 
    
    uint256 private supplyAmount = 0.1 ether;
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        (
            ,, address _weth,,, address _pool,,,
        ) = helperConfig.activeNetworkConfig();

        // user wallet
        user = vm.addr(userKey);

        // create contract instances
        debtManager = DebtManager(payable(helperConfig.debtManagerAddress()));
        aave = Aave(helperConfig.aaveAddress());
        weth = MockERC20(_weth);
        mockPool = MockAaveV3Pool(_pool);

        vm.startBroadcast(userKey);

        // mint WETH
        weth.mint(user, supplyAmount);
        // approve WETH to be spent by debt manager
        weth.approve(address(debtManager), supplyAmount);
        // supply WETH to the protocol
        debtManager.depositCollateralERC20(_weth, supplyAmount);

        vm.stopBroadcast();

        console2.log("Successfully supplied WETH to the protocol!");

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
        ) = aave.getUserAccountData(address(debtManager));

        console2.log("Protocol's Aave position after supplying:");
        console2.log("Collateral in USD:", collateralUSD);
        console2.log("Debt in USD:", debtUSD);
        console2.log("Available to borrow in USD:", canBorrowUSD);
        console2.log("Available to borrow in USDC:", canBorrowUSDC);
        console2.log("Current Liquidation Threshold:", _currentLiquidationThreshold);
        console2.log("Loan to Value ratio:", _ltv);

        // Log protocol's health factor after supplying
        (uint256 hf, HealthStatus status) = aave.getHealthFactor(address(debtManager));
        console2.log("Protocol's health factor after supplying:", hf);
        console2.log("Protocol's health status after supplying:", uint256(status));

        // Log protocol's supply balance in WETH after supplying
        uint256 supplyBalance = aave.getSupplyBalance(address(debtManager), address(weth));
        console2.log("Protocol's supply balance in WETH:", supplyBalance);
    }
}
