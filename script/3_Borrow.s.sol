// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import "forge-std/console2.sol";
import { Aave } from  "../src/Aave.sol";
import { DebtManager } from "../src/DebtManager.sol";
import { HealthStatus } from "../src/Types.sol";

/// @notice This script supplies ETH to the protocol
contract Borrow is Script {
    DebtManager private debtManager;
    Aave private aave;

    address private DebtManagerAddress = 0xFB56BcBB16eF411Ad25EE507d7c2430e561ae3E0;
    address private WETH = 0x6de4964bfEbCa1848c74FeaA6736b14898DfDB0c;
    
    uint256 private borrowAmount = 1200e6;
    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");

    function run() external {
        // Initialize the DebtManager contract
        debtManager = DebtManager(payable(DebtManagerAddress));

        vm.startBroadcast(USER);

        uint32 nextAct = debtManager.getNextActivity(vm.addr(USER));
        uint32 _now = uint32(block.timestamp);
        console2.log("Next: %s", nextAct);
        console2.log("Now: %s", _now);
        console2.log("Can Borrow: %s", nextAct > _now);
        console2.log("------------------------------------------------------------");
        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(USER));
        (uint256 aaveDebtBefore, ) = debtManager.getUserDebt(vm.addr(USER));
        uint256 balance = debtManager.getCollateralBalanceOfUser(vm.addr(USER), WETH);
        console2.log("User collateral balance from DebtManager: %s WETH", balance / 1e18);
        console2.log("User Health Factor before borrow: %s", hfBefore);
        console2.log("User Debt before borrow: %s USDC", aaveDebtBefore / 1e6);
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

