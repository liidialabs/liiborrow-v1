// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { Aave } from  "../src/Aave.sol";

contract DeployAave is Script {
    Aave public aave;

    function run() external returns (Aave) {
        // Deploy HelperConfig to get active network config
        HelperConfig helperConfig = new HelperConfig();
        // Get token, pool & oracle addresses from the active network config
        (
            ,,,,
            address usdc,
            address pool,
            address oracle,
            address dataProvider,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        
        vm.startBroadcast(deployerKey);
        aave = new Aave(pool, oracle, dataProvider, usdc);
        vm.stopBroadcast();

        return aave;
    }
}
