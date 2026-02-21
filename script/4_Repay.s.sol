// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { Aave } from  "../src/Aave.sol";
import { HealthStatus } from "../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice This script repays debt in the protocol
contract Repay is Script {
    DebtManager private debtManager;
    Aave private aave;

    address private DebtManagerAddress = 0x7EDcd4EC208E536e05aBE97213B54cb77E8007ce; 
    address private aaveAddress = 0x555d05ccf5590068679c07519445705f9f8CB62f; 
    address private USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; 
    address private user = 0xC099f8A2C5117C81652A506aFfE10a6E77e79808; 
    
    uint256 private repayAmount = 100.6e6;
    uint256 private deployerKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Initialize the DebtManager & Aave contract
        debtManager = DebtManager(payable(DebtManagerAddress));
        aave = Aave(aaveAddress);

        /* ------------------------------------------------------------------------- */

        uint256 balanceBefore = aave.getVariableDebt(DebtManagerAddress, USDC);
        (uint256 aaveDebt, uint256 totalDebt) = debtManager.getPlatformDebt();

        console2.log("Platform Variable Balance before repayment:", balanceBefore);
        console2.log("Platform Aave debt:", aaveDebt);
        console2.log("Platform total debt:", totalDebt);

        // Log user's debt after repayment
        (uint256 userAaveDebt, uint256 userTotalDebt) = debtManager.getUserDebt(user);
        uint256 userShares = debtManager.getUserShares(user);
        uint256 hf = debtManager.getHealthFactor(user);

        console2.log("User's debt before repayment:");
        console2.log("User Aave debt:", userAaveDebt);
        console2.log("User total debt:", userTotalDebt);
        console2.log("User shares:", userShares);
        console2.log("User health factor:", hf);
        console2.log("Total Debt Shares before repayment:", debtManager.getTotalDebtShares());

        console2.log("--------------------------------------------------------------------------");

        /* ------------------------------------------------------------------------- */

        vm.startBroadcast(deployerKey);

        // Approve USDC for repayment
        IERC20(USDC).approve(DebtManagerAddress, repayAmount);
        // repay USDC debt
        debtManager.repayUsdc(repayAmount);

        vm.stopBroadcast();

        console2.log("Successfully repaid USDC debt!");

        /* ---------------------------------------------------------------------------------- */

        // Log platform's variable debt, total debt and protocol revenue after repayment
        uint256 _balanceAfter = aave.getVariableDebt(DebtManagerAddress, USDC);
        (uint256 _aaveDebt, uint256 _totalDebt) = debtManager.getPlatformDebt();
        uint256 revenue = debtManager.getProtocolRevenue();

        console2.log("Platform Variable Balance after repayment:", _balanceAfter);
        console2.log("Platform Aave debt:", _aaveDebt);
        console2.log("Platform total debt:", _totalDebt);
        console2.log("Protocol revenue:", revenue);

        // Log user's debt after repayment
        (uint256 _userAaveDebt, uint256 _userTotalDebt) = debtManager.getUserDebt(user);
        uint256 _userShares = debtManager.getUserShares(user);
        uint256 _hf = debtManager.getHealthFactor(user);

        console2.log("User Aave debt:", _userAaveDebt);
        console2.log("User total debt:", _userTotalDebt);
        console2.log("User shares:", _userShares);
        console2.log("User health factor:", _hf);
        console2.log("Total Debt Shares after repayment:", debtManager.getTotalDebtShares());

        // Log protocol's health factor after repayment
        (uint256 _protocolHf, HealthStatus _protocolStatus) = aave.getHealthFactor(DebtManagerAddress);
        console2.log("Protocol's health factor after repayment:", _protocolHf);
        console2.log("Protocol's health status after repayment:", uint256(_protocolStatus));
    
    }
}
