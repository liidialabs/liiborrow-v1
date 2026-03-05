// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { Aave } from  "../src/Aave.sol";
import { HealthStatus } from "../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/// @notice This script repays debt in the protocol
contract Repay is Script {
    DebtManager private debtManager;
    Aave private aave;
    HelperConfig private helperConfig;
    MockERC20 private asset;
    
    uint256 private repayAmount = 300e6;
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Deploy HelperConfig to get active network config
        helperConfig = new HelperConfig();
        // Get token, pool & oracle addresses from the active network config
        (
            ,,,,
            address usdc,
            ,,,
        ) = helperConfig.activeNetworkConfig();

        // Initialize the DebtManager & Aave contract
        debtManager = DebtManager(payable(helperConfig.debtManagerAddress()));
        aave = Aave(helperConfig.aaveAddress());
        asset = MockERC20(usdc);

        address USER = vm.addr(userKey);

        /* ------------------------------------------------------------------------- */

        uint256 balanceBefore = aave.getVariableDebt(helperConfig.debtManagerAddress(), usdc);
        (uint256 aaveDebt, uint256 totalDebt) = debtManager.getPlatformDebt();

        console2.log("Platform Variable Balance before repayment:", balanceBefore);
        console2.log("Platform Aave debt:", aaveDebt);
        console2.log("Platform total debt:", totalDebt);

        // Log user's debt after repayment
        (uint256 userAaveDebt, uint256 userTotalDebt) = debtManager.getUserDebt(USER);
        uint256 hf = debtManager.getHealthFactor(USER);

        console2.log("User's debt before repayment:");
        console2.log("User Aave debt:", userAaveDebt);
        console2.log("User total debt:", userTotalDebt);
        console2.log("User health factor:", hf);

        console2.log("--------------------------------------------------------------------------");

        /* ------------------------------------------------------------------------- */

        vm.startBroadcast(userKey);

        // mint to user
        asset.mint(USER ,repayAmount);
        // approve USDC for repayment
        asset.approve(helperConfig.debtManagerAddress(), repayAmount);
        // repay USDC debt
        debtManager.repayUsdc(repayAmount);

        vm.stopBroadcast();

        console2.log("Successfully repaid USDC debt!");

        /* ---------------------------------------------------------------------------------- */

        // Log platform's variable debt, total debt and protocol revenue after repayment
        uint256 _balanceAfter = aave.getVariableDebt(helperConfig.debtManagerAddress(), usdc);
        (uint256 _aaveDebt, uint256 _totalDebt) = debtManager.getPlatformDebt();
        uint256 revenue = debtManager.getProtocolRevenue();

        console2.log("Platform Variable Balance after repayment:", _balanceAfter);
        console2.log("Platform Aave debt:", _aaveDebt);
        console2.log("Platform total debt:", _totalDebt);
        console2.log("Protocol revenue:", revenue);

        // Log user's debt after repayment
        (uint256 _userAaveDebt, uint256 _userTotalDebt) = debtManager.getUserDebt(USER);
        uint256 _hf = debtManager.getHealthFactor(USER);

        console2.log("User Aave debt:", _userAaveDebt);
        console2.log("User total debt:", _userTotalDebt);
        console2.log("User health factor:", _hf);
        console2.log("Total Debt Shares after repayment:", debtManager.getTotalDebtShares());

        // Log protocol's health factor after repayment
        (uint256 _protocolHf, HealthStatus _protocolStatus) = aave.getHealthFactor(helperConfig.debtManagerAddress());
        console2.log("Protocol's health factor after repayment:", _protocolHf);
        console2.log("Protocol's health status after repayment:", uint256(_protocolStatus));
    
    }
}
