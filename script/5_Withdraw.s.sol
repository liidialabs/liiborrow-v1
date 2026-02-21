// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { Aave } from  "../src/Aave.sol";
import { HealthStatus } from "../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice This script withdraws debt in the protocol
contract Withdraw is Script {
    DebtManager private debtManager;
    Aave private aave;

    address private DebtManagerAddress = 0x7EDcd4EC208E536e05aBE97213B54cb77E8007ce;
    address private aaveAddress = 0x555d05ccf5590068679c07519445705f9f8CB62f;
    address private WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address private user = 0xC099f8A2C5117C81652A506aFfE10a6E77e79808;
    
    uint256 private withdrawAmount = 0.05 ether;
    uint256 private deployerKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Initialize the DebtManager & Aave contract
        debtManager = DebtManager(payable(DebtManagerAddress));
        aave = Aave(aaveAddress);

        vm.startBroadcast(deployerKey);

        // withdraw Weth from debt
        debtManager.redeemCollateral(WETH, withdrawAmount, true);

        vm.stopBroadcast();

        console2.log("Successfully withdrew collateral supplied");

        // Log platform's
        uint256 balanceAfter = aave.getSupplyBalance(DebtManagerAddress, WETH);
        (uint256 aaveDebt, uint256 totalDebt) = debtManager.getPlatformDebt();
        console2.log("Platform supply balance in WETH after withdrawal:", balanceAfter);
        console2.log("Platform Aave debt:", aaveDebt);
        console2.log("Platform total debt:", totalDebt);

        // Log protocol's health factor after repayment
        (uint256 protocolHf, HealthStatus protocolStatus) = aave.getHealthFactor(DebtManagerAddress);
        console2.log("Protocol's health factor after withdrawal:", protocolHf);
        console2.log("Protocol's health status after withdrawal:", uint256(protocolStatus));
    
    }
}
