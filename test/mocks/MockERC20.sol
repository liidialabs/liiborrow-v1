// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for testing with configurable decimals
 * @dev Includes mint/burn functions for easy test setup
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    // Control flags for testing
    bool public shouldRevertOnTransfer;
    bool public shouldRevertOnTransferFrom;
    bool public shouldRevertOnApprove;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    /**
     * @notice Override decimals to support custom decimal places
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint tokens to an address
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    /**
     * @notice Burn tokens from an address
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
    
    /**
     * @notice Mint tokens to msg.sender (convenience function)
     */
    function mintSelf(uint256 amount) external {
        _mint(msg.sender, amount);
    }
    
    /**
     * @notice Burn tokens from msg.sender (convenience function)
     */
    function burnSelf(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    // ============ CONTROL FUNCTIONS FOR TESTING ============
    
    /**
     * @notice Control whether transfer should revert
     */
    function setShouldRevertOnTransfer(bool _shouldRevert) external {
        shouldRevertOnTransfer = _shouldRevert;
    }
    
    /**
     * @notice Control whether transferFrom should revert
     */
    function setShouldRevertOnTransferFrom(bool _shouldRevert) external {
        shouldRevertOnTransferFrom = _shouldRevert;
    }
    
    /**
     * @notice Control whether approve should revert
     */
    function setShouldRevertOnApprove(bool _shouldRevert) external {
        shouldRevertOnApprove = _shouldRevert;
    }
    
    // ============ OVERRIDE FUNCTIONS FOR TESTING ============
    
    /**
     * @notice Override transfer to support controlled failures
     */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        require(!shouldRevertOnTransfer, "MockERC20: transfer reverted");
        return super.transfer(to, amount);
    }
    
    /**
     * @notice Override transferFrom to support controlled failures
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        require(!shouldRevertOnTransferFrom, "MockERC20: transferFrom reverted");
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @notice Override approve to support controlled failures
     */
    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        require(!shouldRevertOnApprove, "MockERC20: approve reverted");
        return super.approve(spender, amount);
    }
    
    // ============ HELPER FUNCTIONS ============
    
    /**
     * @notice Directly set balance for testing (bypasses normal mint logic)
     * @dev Useful for testing specific balance scenarios
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
     * @notice Set allowance directly for testing
     */
    function setAllowance(
        address owner,
        address spender,
        uint256 amount
    ) external {
        // This is a bit of a hack, but useful for testing
        // We need to manipulate internal state
        _approve(owner, spender, amount);
    }
    
    /**
     * @notice Reset all revert flags (useful between tests)
     */
    function resetRevertFlags() external {
        shouldRevertOnTransfer = false;
        shouldRevertOnTransferFrom = false;
        shouldRevertOnApprove = false;
    }
}