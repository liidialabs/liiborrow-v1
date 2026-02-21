// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";

contract DeployDebtManager is Script {
    address[] public recievedTokenAddresses;
    address[] public tokenAddresses;

    Aave public aave;
    DebtManager public debtManager;
    HelperConfig public helperConfig;

    function run() external returns (Aave, DebtManager) {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        // Get token, pool & oracle addresses from the active network config
        (
            address cbeth,
            address cbbtc,
            address weth,
            address wbtc,
            address usdc,
            address pool,
            address oracle,
            address dataProvider,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        // Prepare token addresses array
        recievedTokenAddresses = [cbeth, cbbtc, weth, wbtc, usdc];
        for (uint256 i = 0; i < recievedTokenAddresses.length; i++) {
            if (recievedTokenAddresses[i] != address(0)) {
                tokenAddresses.push(recievedTokenAddresses[i]);
            }
        }

        vm.startBroadcast(deployerKey);

        // deploy aave
        aave = new Aave(pool, oracle, dataProvider, usdc);
        // deploy debt manager
        debtManager = new DebtManager(tokenAddresses, address(aave), usdc, weth);
        
        vm.stopBroadcast();

        console2.log("Successfully deployed contracts!");
        console2.log("Deployed Aave at:", address(aave));
        console2.log("Deployed DebtManager at:", address(debtManager));

        return (aave, debtManager);
    }
}
