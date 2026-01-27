// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockWETH
 * @notice Mock Wrapped Ether for testing
 * @dev Implements deposit/withdraw functionality like real WETH
 */
contract MockWETH is ERC20 {
    
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    
    // Control flags for testing
    bool public shouldRevertOnDeposit;
    bool public shouldRevertOnWithdraw;
    
    constructor() ERC20("Wrapped Ether", "WETH") {}
    
    /**
     * @notice Returns 18 decimals (standard for WETH)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    /**
     * @notice Deposit ETH and receive WETH
     */
    function deposit() public payable {
        require(!shouldRevertOnDeposit, "MockWETH: deposit reverted");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @notice Withdraw WETH and receive ETH
     */
    function withdraw(uint256 wad) public {
        require(!shouldRevertOnWithdraw, "MockWETH: withdraw reverted");
        require(balanceOf(msg.sender) >= wad, "MockWETH: insufficient balance");
        
        _burn(msg.sender, wad);
        
        (bool success,) = msg.sender.call{value: wad}("");
        require(success, "MockWETH: ETH transfer failed");
        
        emit Withdrawal(msg.sender, wad);
    }
    
    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {
        deposit();
    }
    
    /**
     * @notice Fallback function - calls deposit
     */
    fallback() external payable {
        deposit();
    }
    
    // ============ TESTING CONTROL FUNCTIONS ============
    
    /**
     * @notice Control whether deposit should revert
     */
    function setShouldRevertOnDeposit(bool _shouldRevert) external {
        shouldRevertOnDeposit = _shouldRevert;
    }
    
    /**
     * @notice Control whether withdraw should revert
     */
    function setShouldRevertOnWithdraw(bool _shouldRevert) external {
        shouldRevertOnWithdraw = _shouldRevert;
    }
    
    /**
     * @notice Reset all revert flags
     */
    function resetRevertFlags() external {
        shouldRevertOnDeposit = false;
        shouldRevertOnWithdraw = false;
    }
    
    // ============ HELPER FUNCTIONS FOR TESTING ============
    
    /**
     * @notice Mint WETH directly (for test setup)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    /**
     * @notice Burn WETH directly (for test setup)
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
    
    /**
     * @notice Set balance directly (for test setup)
     */
    function setBalance(address account, uint256 amount) external {
        uint256 currentBalance = balanceOf(account);
        
        if (amount > currentBalance) {
            _mint(account, amount - currentBalance);
        } else if (amount < currentBalance) {
            _burn(account, currentBalance - amount);
        }
    }
    
    /**
     * @notice Fund contract with ETH for testing withdrawals
     */
    function fundWithETH() external payable {}
}