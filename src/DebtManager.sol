// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ErrorsLib } from "./libraries/ErrorsLib.sol";
import { EventsLib } from "./libraries/EventsLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Aave } from "./Aave.sol";
import { IPool } from "./interfaces/aave-v3/IPool.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { HealthStatus, UserCollateral, LiquidationEarnings } from "./Types.sol";

/*
 * @title GoLiquid 
 * @author Caleb Mokua
 * @description It's a CDP (Collateralized Debt Position) Protocol built on top of Aave
 */

contract DebtManager is ReentrancyGuard, Ownable, Pausable {
    // Types
    using SafeERC20 for IERC20;

    // State Variables

    IPool public immutable pool;
    IWETH public immutable weth;
    Aave public immutable aave;
    uint256 private immutable VTOKEN_DEC_PRECISION;
    address private immutable USDC;
    
    address private constant ETH = address(0);
    uint256 private constant AAVE_LTV_PRECISION = 1e4; // 10000 = 100%
    uint256 private constant PLATFORM_AAVE_LTV_DIFF = 1e3; // 1000 = 10%
    uint256 private constant DEFAULT_LIQUIDATION_CLOSE_FACTOR = 0.5e18; // wad (1e18), e.g. 50% = 0.5e18
    uint256 private constant MAX_LIQUIDATION_CLOSE_FACTOR = 1e18; // wad (1e18), e.g. 100% = 1e18
    uint256 private constant CLOSE_FACTOR_HF_THRESHOLD = 0.95e18; // wad (1e18), e.g. 95% = 0.95e18
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant DANGER_ZONE = 1.1e18;
    uint256 private constant BASE_PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant USD_PRECISION = 1e8;
    uint256 private constant USDC_PRECISION = 1e6;
    uint256 private constant BASE_APR = 0.005e18; // wad (1e18), e.g. 0.5% = 0.005e18
    uint256 private constant BASE_BONUS = 0.01e18; // wad (1e18), e.g. 1% = 0.01e18
    uint256 private constant MAX_COOLDOWN = 30 minutes;

    uint256 private s_coolDownPeriod = 10 minutes;
    uint256 private s_liquidationFee = 0.01e18; // initial at 1%

    // platform ltv & lltv  based on aave's platform account data
    uint256 private s_platformLtv;
    uint256 private s_platformLltv;

    uint256 private aaveDebt;          // in underlying asset (wad)
    uint256 private totalDebt;        // aave debt + protocol spread
    uint256 private s_totalDebtShares;  // abstract shares
    uint256 private s_protocolRevenueAccrued;  // in underlying asset (wad)
    uint256 private protocolAPRMarkup = 0.005e18;   // wad (1e18), e.g. 1% = 0.01e18
    HealthStatus private healthStatus;

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => bool isSupported) private s_supportedCollateral;
    /// @dev Enforce collateral token activity freezing
    mapping(address collateralToken => bool isPaused) private s_collateralPaused;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited; // Tracks user's deposit position
    /// @dev Amount of USDC borrowed
    mapping(address user => uint256 amount) private s_userDebtShares; // Tracks user's debt position
    /// @dev enforce s_coolDownPeriod after deposit deposit and repayment
    mapping(address user => uint32 nextActivity) private s_coolDown;
    /// @dev total collateral supplied
    mapping(address collateral => uint256 amount) private s_totalColSupplied;
    /// @dev Earnings through liquidation
    mapping(address collateral => uint256 amount) private s_liquidationRevenue;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    address[] private s_collateralTokens;

    // Modifiers

    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isSupportedToken(address token) {
        _isSupportedToken(token);
        _;
    }

    modifier isCollateralPaused(address token) {
        _isCollateralPaused(token);
        _;
    }

    modifier enforceCooldown {
        _enforceCooldown();
        _;
    }

    // CONSTRUCTOR

    constructor(
        address[] memory tokenAddresses, 
        address _aave,
        address _usdc,
        address _weth
    ) Ownable(msg.sender) {
        if (tokenAddresses.length == 0) {
            revert ErrorsLib.DebtManager__CollateralAssetsNotParsed();
        }
        // map token addresses to price feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if(tokenAddresses[i] == ETH) {
                revert ErrorsLib.DebtManager__ZeroAddress();
            }
            s_collateralTokens.push(tokenAddresses[i]);
            s_supportedCollateral[tokenAddresses[i]] = true;
        }
        //
        aave = Aave(_aave);
        pool = aave.pool();
        VTOKEN_DEC_PRECISION =  10 ** aave.vTokenDecimals();
        //
        weth = IWETH(_weth);
        USDC = _usdc;
    }

    // Receive ETH

    /**
     * @dev Called when the contract receives ETH with empty calldata.
     *      Required to accept direct ETH transfers: address(this).transfer(...)
     */
    receive() external payable {}

    /**
     * @dev Called when the contract receives ETH with non-empty calldata
     *      or when no function matches the call data.
     *      Must be payable to allow receiving ETH via .call().
     */
    fallback() external payable {}


    // External Functions

    /**
     * @param tokenCollateralAddress: The ERC20 token address of the collateral being deposited
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateralERC20(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public isCollateralPaused(tokenCollateralAddress) moreThanZero(amountCollateral) nonReentrant isSupportedToken(tokenCollateralAddress) whenNotPaused {
        s_coolDown[msg.sender] = uint32(block.timestamp + s_coolDownPeriod);
        s_totalColSupplied[tokenCollateralAddress] += amountCollateral;
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit EventsLib.CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        IERC20(tokenCollateralAddress).safeTransferFrom(msg.sender, address(this), amountCollateral);
        IERC20(tokenCollateralAddress).approve(address(pool), amountCollateral);

        // Aave supply logic
        pool.supply({
            asset: tokenCollateralAddress,
            amount: amountCollateral,
            onBehalfOf: address(this),
            referralCode: 0
        });
    }

    /**
     * @dev Deposited ETH is wrapped into WETH before being supplied to Aave
     * @param amountCollateral: The amount of collateral being deposited (ETH)
     */
    function depositCollateralETH(uint256 amountCollateral) payable external moreThanZero(msg.value) nonReentrant whenNotPaused {
        s_coolDown[msg.sender] = uint32(block.timestamp + s_coolDownPeriod);

        if(msg.value != amountCollateral) {
            revert ErrorsLib.DebtManager__AmountNotEqual();
        }
        s_totalColSupplied[ETH] += amountCollateral;
        /// @notice Since we cannot use ETH as an ERC20 we'll add it also to WETH
        s_collateralDeposited[msg.sender][ETH] += amountCollateral;
        s_collateralDeposited[msg.sender][address(weth)] += amountCollateral;
        emit EventsLib.CollateralDeposited(msg.sender, ETH, amountCollateral);

        // Aave supply logic
        weth.deposit{value: msg.value}();
        IERC20(address(weth)).approve(address(pool), msg.value);
        pool.supply({
            asset: address(weth),
            amount: msg.value,
            onBehalfOf: address(this),
            referralCode: 0
        });
    }

    /**
     * @dev HF should remain above 1 after redeeming collateral
     * @notice Users can only redeem up to the max amount that keeps their HF above 1
     * @param collateral: The ERC20 token address of the collateral being redeemed
     * @param amountCollateral: The amount of collateral being redeemed
     * @param isEth: Boolean to indicate if the collateral being redeemed is ETH
     */
    function redeemCollateral(
        address collateral,
        uint256 amountCollateral,
        bool isEth
    ) external moreThanZero(amountCollateral) nonReentrant isSupportedToken(collateral) enforceCooldown whenNotPaused {
        s_coolDown[msg.sender] = uint32(block.timestamp + s_coolDownPeriod);

        uint256 _amountCollateral = s_collateralDeposited[msg.sender][collateral];
        if(_amountCollateral == 0) {
            revert ErrorsLib.DebtManager__InsufficientCollateral();
        }

        uint256 maxAmount = _maxWithdrawAmount(msg.sender, collateral);
        if(amountCollateral > maxAmount) {
            amountCollateral = maxAmount;
        }
        if(isEth) {
            s_collateralDeposited[msg.sender][ETH] -= amountCollateral;
        }
        s_collateralDeposited[msg.sender][collateral] -= amountCollateral;

        _redeemCollateral(collateral, amountCollateral, false, isEth);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Borrowing USDC limited to amounts that wont break HF, calculated locally based on DebtManager's Aave position
     * @notice Users can only borrow up to the max amount that keeps their HF above 1.0
     * @param amountToBorrow: The amount of USDC to borrow
     */
    function borrowUsdc(uint256 amountToBorrow) external nonReentrant moreThanZero(amountToBorrow) enforceCooldown whenNotPaused {
        // update platform ltv & lltv
        _currentPlatformLtvAndLltv();

        // check if supplied collateral
        (,, uint256 collateralValueInUsd) = _getAccountInformation(msg.sender);
        if(collateralValueInUsd == 0) {
            revert ErrorsLib.DebtManager__NoCollateralSupplied();
        }

        uint256 maxBorrowAmount = _maxBorrowAmount(msg.sender);
        if(amountToBorrow > maxBorrowAmount) {
            amountToBorrow = maxBorrowAmount;
        }
        
        aave.revertIfHFBreaks(amountToBorrow, address(this));
        _currentPlatformDebt();
        _borrowUsd(amountToBorrow);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @dev Repayment of USDC debt, partial or full. Protocol cut is taken here.
     * @notice If user is repaying more than they owe, excess is ignored
     * @param amountToRepay: The amount of USDC to repay
     */
    function repayUsdc(uint256 amountToRepay) external nonReentrant moreThanZero(amountToRepay) whenNotPaused {
        // check if borrowed
        (uint256 totalUsdcBorrowedInUsd,,) = _getAccountInformation(msg.sender);
        if(totalUsdcBorrowedInUsd == 0) {
            revert ErrorsLib.DebtManager__NoAssetBorrowed();
        }
        // check if excess
        (,uint256 userTotalDebt) = _debtOwed(msg.sender); // NB: Current protocol debt is updated here
        if(amountToRepay > userTotalDebt) {
            amountToRepay = userTotalDebt;
        }

        _repayUsdc(amountToRepay);
    }

    /**
     * @notice APR cannot be set below base APR
     * @param _newAPR: The new APR spread
     */
    function setProtocolAPRMarkup(uint256 _newAPR) external nonReentrant onlyOwner {
        if(_newAPR < BASE_APR) {
            revert ErrorsLib.DebtManager__BelowBaseApr();
        }
        protocolAPRMarkup = _newAPR;
    }

    /**
     * @notice Liquidation fee cannot be set below base APR
     * @param _newFee: The new liquidation fee
     */
    function setLiquidationFee(uint256 _newFee) external nonReentrant onlyOwner {
        if(_newFee < BASE_APR) {
            revert ErrorsLib.DebtManager__BelowBaseApr();
        }
        s_liquidationFee = _newFee;
    }

    /**
     * @notice Cool down period cannot be set above max cool down
     * @param _newCoolDown: The new cool down period
     */
    function setCoolDownPeriod(uint256 _newCoolDown) external nonReentrant onlyOwner {
        if(_newCoolDown > MAX_COOLDOWN) {
            revert ErrorsLib.DebtManager__ExceedsMaxCoolDown();
        }
        s_coolDownPeriod = _newCoolDown;
    }

    /**
     * @dev Add a new collateral asset to the system
     * @param collateral: Address of the asset to add
     */
    function addCollateralAsset(address collateral) external onlyOwner {
        if(collateral == ETH) {
            revert ErrorsLib.DebtManager__ZeroAddress();
        }
        s_collateralTokens.push(collateral);
        s_supportedCollateral[collateral] = true;
    }

    /**
     * @dev Pauses collateral activity(deposits) for a specific asset
     * @param collateral: Address of the asset to pause
     */
    function pauseCollateralActivity(address collateral) external onlyOwner {
        if (collateral == ETH) {
            revert ErrorsLib.DebtManager__ZeroAddress();
        }
        if(s_collateralPaused[collateral]) {
            revert ErrorsLib.DebtManager__CollateralAlreadyPaused(collateral);
        }
        s_collateralPaused[collateral] = true;
    }

    /**
     * @dev Unpauses collateral activity(deposits) for a specific asset
     * @param collateral: Address of the asset to unpause
     */
    function unPauseCollateralActivity(address collateral) external onlyOwner {
        if (collateral == ETH) {
            revert ErrorsLib.DebtManager__ZeroAddress();
        }
        if(!s_collateralPaused[collateral]) {
            revert ErrorsLib.DebtManager__CollateralNotPaused(collateral);
        }
        s_collateralPaused[collateral] = false;
    }

    /**
     * @notice Pause the contract
     * @dev Only callable by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Get user's LTV, based on internal platform calculations based on DebtManager's Aave position
     * @param user The address of the user
     * @return ltv The user's loan-to-value ratio (LTV) in wad (1e18)
     */
    function userLTV(address user) public returns(uint256 ltv) {
        _currentPlatformLtvAndLltv(); // update platform ltv & lltv

        (uint256 totalUsdcBorrowedInUsd,, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalUsdcBorrowedInUsd == 0 || collateralValueInUsd == 0) return type(uint256).max;

        ltv = (totalUsdcBorrowedInUsd * BASE_PRECISION) / collateralValueInUsd;
    }

    /**
     * @notice Check if user is liquidatable based on internal platform calculations based on DebtManager's Aave position
     * @param user: The address of the user
     * @return bool: True if liquidatable, false otherwise
     */
    function isLiquidatable(address user) public returns (bool) {
        uint256 ltv = userLTV(user);

        if(ltv == type(uint256).max) {
            return false; // no debt or no collateral
        }
        return ltv >= s_platformLltv;
    }

    /**
     * @dev Liquidation only happens when user is liquidatable & if it improves their health factor
     * @param user: The address of the user to liquidate
     * @param collateral: The asset to recieve
     * @param repayAmount: The amount to pay onbehalf of user
     * @param isEth: Boolean to indicate if the collateral being redeemed is ETH
     */
    function liquidate(
        address user,
        address collateral, 
        uint256 repayAmount,
        bool isEth
    ) external nonReentrant isSupportedToken(collateral) moreThanZero(repayAmount) whenNotPaused {      
        // check if liquidatable
        if(!isLiquidatable(user)) {
            revert ErrorsLib.DebtManager__UserNotLiquidatable();
        }

        // check amount to repay & user's hf
        (uint256 userAaveDebt,) = _debtOwed(user);
        uint256 currentHFactor = _healthFactor(user);

        // apply close factor
        uint256 closeFactor;
        if(currentHFactor >= CLOSE_FACTOR_HF_THRESHOLD) {
            closeFactor = DEFAULT_LIQUIDATION_CLOSE_FACTOR;
        } else {
            closeFactor = MAX_LIQUIDATION_CLOSE_FACTOR;
        }
        uint256 maxRepay = (userAaveDebt * closeFactor) / BASE_PRECISION;
        if(repayAmount > maxRepay) {
            repayAmount = maxRepay;
        }

        // collateral to seize
        uint256 valueOfRepayAmount = _getUsdValue(USDC, repayAmount);
        uint256 amountOfCollateralToSeize = getCollateralAmountLiquidate(collateral, valueOfRepayAmount);
        amountOfCollateralToSeize = (amountOfCollateralToSeize * (BASE_PRECISION + s_liquidationFee)) / BASE_PRECISION; // add liquidation fee

        if(s_collateralDeposited[user][collateral] < amountOfCollateralToSeize) {
            revert ErrorsLib.DebtManager__InsufficientCollateral();
        }

        // transfer
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), repayAmount);
        IERC20(USDC).approve(address(pool), repayAmount);
        pool.repay({
            asset: USDC,
            amount: repayAmount,
            interestRateMode: 2,
            onBehalfOf: address(this)
        });

        // Burn liquidated user's shares
        uint256 sharesToBurn = _sharesToBurn(repayAmount);
        s_userDebtShares[user] -= sharesToBurn;
        s_totalDebtShares -= sharesToBurn;

        // Seize and transfer collateral
        if(isEth) {
            s_collateralDeposited[user][ETH] -= amountOfCollateralToSeize;
        }
        s_collateralDeposited[user][collateral] -= amountOfCollateralToSeize;
        _redeemCollateral(collateral, amountOfCollateralToSeize, true, isEth);
        _revertIfHealthFactorIsBroken(user);

        emit EventsLib.Liquidated(msg.sender, user, collateral, repayAmount, uint32(block.timestamp));
    }

    /* WITHDRAW FROM CONTRACT */

    /**
     * @dev Withdraw accrued revenue from protocol operations
     * @notice Only callable by the contract owner
     * @param to: The address to send the revenue to, a treasury
     * @param asset: The asset to withdraw
     * @param amount: The amount to withdraw
     */
    function withdrawRevenue(
        address to, 
        address asset, 
        uint256 amount
    ) external moreThanZero(amount) isSupportedToken(asset) nonReentrant onlyOwner {
        if(to == ETH || asset == ETH) {
            revert ErrorsLib.DebtManager__ZeroAddress();
        }
        if(asset == USDC) {
            if(amount > s_protocolRevenueAccrued || s_protocolRevenueAccrued == 0) {
                revert ErrorsLib.DebtManager__InsufficientAmountToWithdraw();
            }
            s_protocolRevenueAccrued -= amount;
        } else {
            uint256 revenue = s_liquidationRevenue[asset];
            if(amount > revenue || revenue == 0) {
                revert ErrorsLib.DebtManager__InsufficientAmountToWithdraw();
            }
            s_liquidationRevenue[asset] -= amount;
        }

        IERC20(asset).safeTransfer(to, amount);
        emit EventsLib.RevenueWithdrawn(to, asset, amount, uint32(block.timestamp));
    }


    // Private Functions


    /**
     * @dev Calls the Aave borrow function and updates user debt shares
     * @param amountToBorrow: The amount of USDC to borrow
     */
    function _borrowUsd(uint256 amountToBorrow) private {
        s_coolDown[msg.sender] = uint32(block.timestamp + s_coolDownPeriod);

        uint256 shares; // to 1e18
        if (s_totalDebtShares == 0) {
            shares = amountToBorrow * BASE_PRECISION / USDC_PRECISION; 
        } else {
            shares = _sharesToGet(amountToBorrow);
        }
        s_userDebtShares[msg.sender] += shares;
        s_totalDebtShares += shares;

        emit EventsLib.BorrowedUsdc(msg.sender, amountToBorrow, uint32(block.timestamp));

        // aave logic
        pool.borrow({
            asset: USDC,
            amount: amountToBorrow,
            // 1 = Stable interest rate
            // 2 = Variable interest rate
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: address(this)
        });

    }

    /**
     * @dev Calls the Aave repay function and updates user debt shares
     * @param amountToRepay: The amount of USDC to repay
     */
    function _repayUsdc(uint256 amountToRepay) private {
        // take platform cut
        (uint256 aaveCut, uint256 protocolCut) = _repayCut(amountToRepay);
        s_protocolRevenueAccrued += protocolCut;
        
        uint256 sharesToBurn = _sharesToBurn(aaveCut);
        s_userDebtShares[msg.sender] -= sharesToBurn;
        s_totalDebtShares -= sharesToBurn;
        emit EventsLib.RepayUsdc(msg.sender, amountToRepay, uint32(block.timestamp));

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amountToRepay);

        // aave logic
        IERC20(USDC).approve(address(pool), aaveCut);
        pool.repay({
            asset: USDC,
            amount: aaveCut,
            interestRateMode: 2,
            onBehalfOf: address(this)
        });
    }

    /**
     * @dev Redeem collateral from Aave and transfer to user
     * @notice If isLiquidating is true, a liquidation fee is charged
     * @param collateral: The asset to redeem
     * @param amountCollateral: The amount of collateral to redeem
     * @param isLiquidating: Boolean to indicate if the redemption is part of a liquidation
     * @param isEth: Boolean to indicate if the collateral being redeemed is ETH
     */
    function _redeemCollateral(
        address collateral,
        uint256 amountCollateral,
        bool isLiquidating,
        bool isEth
    ) private {
        uint256 amount;

        // aave logic
        pool.withdraw({asset: collateral, amount: amountCollateral, to: address(this)});

        // charge liquidation fee
        if(isLiquidating) {
            amount = (amountCollateral * BASE_PRECISION) / (BASE_PRECISION + s_liquidationFee);
            s_liquidationRevenue[collateral] += (amountCollateral - amount);
        } else {
            amount = amountCollateral;
        }

        // ETH transfer
        if(isEth) {
            weth.withdraw(amount);
            (bool sent,) = msg.sender.call{value: amount}("");
            if (!sent) {
                revert ErrorsLib.DebtManager__TransferFailed();
            }
            return;
        }
        // ERC20 transfer
        IERC20(collateral).safeTransfer(msg.sender, amount);

        emit EventsLib.CollateralRedeemed(msg.sender, msg.sender, collateral, amountCollateral);
    }

    /**
    * @dev Calculate the maximum borrow value in USD that a user can borrow without breaking their health factor
    * @param user The address of the user
    * @return upto The maximum borrow value in USD
    */
    function _maxBorrowValue(address user) private returns(uint256 upto) {
        (uint256 totalUsdcBorrowedInUsd,, uint256 collateralValueInUsd) = _getAccountInformation(user);
        
        uint256 collateralAdjustedForLtv = (collateralValueInUsd * s_platformLtv) / BASE_PRECISION;
        if(totalUsdcBorrowedInUsd >= collateralAdjustedForLtv) {
            revert ErrorsLib.DebtManager__AlreadyAtBreakingPoint();
        }
        upto = collateralAdjustedForLtv - totalUsdcBorrowedInUsd;
    }

    /**
     * @dev Calculate the maximum borrow amount in USDC that a user can borrow without breaking their health factor
     * @param user The address of the user
     * @return upto The maximum borrow amount in USDC
     */
    function _maxBorrowAmount(address user) private returns(uint256 upto) {
        uint256 maxBorrowValue = _maxBorrowValue(user);

        uint256 price = _getAssetPrice(USDC);
        uint8 tokenDecimals = IERC20Metadata(USDC).decimals();

        upto = (maxBorrowValue * uint256(10 ** tokenDecimals)) / (price * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @dev Calculate the maximum withdrawable amount of collateral that a user can redeem without breaking their health factor
     * @param user The address of the user
     * @param collateral The collateral asset address
     * @return upto The maximum withdrawable amount of collateral
     */
    function _maxWithdrawAmount(address user, address collateral) private returns(uint256 upto) { // Should maintain internal HF at 1
        (uint256 totalUsdcBorrowedInUsd,, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 amountCollateral = s_collateralDeposited[user][collateral];
        uint256 valueCollateral = _getUsdValue(collateral, amountCollateral);

        // Get the value
        uint256 withdrawalValue;
        if(totalUsdcBorrowedInUsd == 0) {
            withdrawalValue = collateralValueInUsd;
        } else {
            uint256 threshold = (collateralValueInUsd * s_platformLtv) / BASE_PRECISION;
            withdrawalValue = threshold - totalUsdcBorrowedInUsd;
        }

        // Get value amount
        if(valueCollateral < withdrawalValue) {
            withdrawalValue = valueCollateral;
        }

        upto = _valueToAmount(collateral, withdrawalValue);
    }

    /**
     * @dev Calculate the amount of collateral based on USD value
     * @param collateral The collateral asset address
     * @param amountValue The USD value of the amount
     * @return amount The amount of collateral
     */
    function _valueToAmount(address collateral, uint256 amountValue) private view returns(uint256 amount) {
        uint256 price = _getAssetPrice(collateral);
        uint8 tokenDecimals = IERC20Metadata(collateral).decimals();

        amount = (amountValue * uint256(10 ** tokenDecimals)) / (price * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @dev Calculate the Aave cut and protocol cut from a repayment amount
     * @param amountBeingRepayed The total amount being repaid
     * @return aaveCut The amount that goes to Aave
     * @return protocolCut The amount that goes to the protocol
     */
    function _repayCut(uint256 amountBeingRepayed) private view returns(uint256 aaveCut, uint256 protocolCut) {
        aaveCut = (amountBeingRepayed * BASE_PRECISION) / (BASE_PRECISION + protocolAPRMarkup);
        protocolCut = amountBeingRepayed - aaveCut;
    }

    /**
     * @dev Calculate the number of debt shares to mint when borrowing
     * @param amountToBorrow The amount of USDC to borrow
     * @return shares The number of debt shares to mint
     */
    function _sharesToGet(uint256 amountToBorrow) private view returns(uint256 shares) {
        shares = (amountToBorrow * s_totalDebtShares * VTOKEN_DEC_PRECISION) / (aaveDebt * USDC_PRECISION);
    }

    /**
     * @dev Calculate the number of debt shares to burn when repaying
     * @param amountToRepay The amount of USDC to repay
     * @return shares The number of debt shares to burn
     */
    function _sharesToBurn(uint256 amountToRepay) private view returns(uint256 shares) {
        shares = (amountToRepay * s_totalDebtShares * VTOKEN_DEC_PRECISION) / (aaveDebt * USDC_PRECISION);
    }


    // Private & Internal View & Pure Functions


    /**
     * @dev Calculate the user's share of debt in USDC
     * @param user The address of the user
     * @return userAaveDebt The amount of debt owed to Aave, 
     * @return userTotalDebt The total amount of debt owed to the protocol and Aave (Aave + protocol cut)
     */
    function _debtOwed(address user) private returns (uint256 userAaveDebt, uint256 userTotalDebt) {
        _currentPlatformDebt();
        if (s_userDebtShares[user] == 0) return (0, 0);
        userAaveDebt = (s_userDebtShares[user] * aaveDebt * USDC_PRECISION) / (s_totalDebtShares * VTOKEN_DEC_PRECISION); // owed to aave
        userTotalDebt = (s_userDebtShares[user] * totalDebt * USDC_PRECISION) / (s_totalDebtShares * VTOKEN_DEC_PRECISION); // owed to protocol + aave
    }

    /**
     * @dev Calculate the current platform debt, Aave debt & protocol Charges + Aave debt
     * @notice Debt remains in original vToken precision
     */
    function _currentPlatformDebt() private {
        aaveDebt = aave.getVariableDebt(address(this), USDC);
        totalDebt = (aaveDebt * (BASE_PRECISION + protocolAPRMarkup)) / BASE_PRECISION;
    }

    /**
     * @dev Calculate the current platform LTV and LLTV based on DebtManager Aave's position
     */
    function _currentPlatformLtvAndLltv() private {
        (,,, uint256 currentLiquidationThreshold, uint256 ltv,) = pool.getUserAccountData(address(this));
        // Convert Aave LTV and LLTV to platform precision
        s_platformLltv = ((currentLiquidationThreshold - PLATFORM_AAVE_LTV_DIFF) * BASE_PRECISION) / AAVE_LTV_PRECISION;
        s_platformLtv = ((ltv - PLATFORM_AAVE_LTV_DIFF) * BASE_PRECISION) / AAVE_LTV_PRECISION;
    }

    /**
    * @dev Get account information for a user  
    * @notice All return values are in USD value (1e18 = 1 USD)
    * @param user The address of the user
    * @return totalUsdcBorrowedInUsd The total USDC borrowed by the user in USD value
    * @return totalUsdcToRepay The total USDC to repay by the user in USD value (including protocol cut)
    * @return collateralValueInUsd The total collateral value of the user in USD
     */
    function _getAccountInformation(address user) private
        returns (uint256 totalUsdcBorrowedInUsd, uint256 totalUsdcToRepay, uint256 collateralValueInUsd)
    {   // Get user's share of debt
        (uint256 userAaveDebt, uint256 userTotalDebt) = _debtOwed(user);
        totalUsdcBorrowedInUsd = _getUsdValue(USDC, userAaveDebt);
        totalUsdcToRepay = _getUsdValue(USDC, userTotalDebt);
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @dev Calculate the health factor of a user based on internal accounting
     * @param user: The address of the user
     * @return hFactor: The health factor of the user
     */
    function _healthFactor(address user) private returns (uint256) {
        _currentPlatformLtvAndLltv(); // update platform ltv & lltv
        (uint256 totalUsdcBorrowedInUsd,, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalUsdcBorrowedInUsd, collateralValueInUsd);
    }

    /**
    * @dev Get the asset price from Aave oracle
    * @param token The address of the token
    * @return price The price of the asset in USD (1e8 = 1 USD)
    */
    function _getAssetPrice(address token) private view returns (uint256 price) {
        // get price (1e8 = 1 USD)
        price = aave.getAssetPrice(token);
    }

    /**
    * @dev Get the USD value of an amount of a token
    * @param token The address of the token
    * @param amount The amount of the token
    * @return value The USD value of the amount in USD (1e18 = 1 USD)
    */
    function _getUsdValue(address token, uint256 amount) private view returns (uint256 value) {
        // get price
        uint256 price = _getAssetPrice(token);
        // get decimals
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        // get value
        value = (price * ADDITIONAL_FEED_PRECISION * amount) / uint256(10 ** tokenDecimals);
    }

    /**
     * @dev Calculate the health factor based on total borrowed and collateral value
     * @param totalUsdcBorrowedInUsd The total USDC borrowed by the user in USD value
     * @param collateralValueInUsd The total collateral value of the user in USD
     * @return hFactor The health factor of the user
     */
    function _calculateHealthFactor(
        uint256 totalUsdcBorrowedInUsd,
        uint256 collateralValueInUsd
    ) internal view returns (uint256 hFactor) {
        if (totalUsdcBorrowedInUsd == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * s_platformLltv) / BASE_PRECISION;
        hFactor = (collateralAdjustedForThreshold * BASE_PRECISION) / totalUsdcBorrowedInUsd;
    }

    /**
     * @dev Revert if user's health factor is below the minimum threshold
     * @param user: The address of the user
     */
    function _revertIfHealthFactorIsBroken(address user) internal {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert ErrorsLib.DebtManager__BreaksHealthFactor();
        }
    }

    /**
    * @dev Enforce cooldown period for user actions
    */
    function _enforceCooldown() internal view {
        if(s_coolDown[msg.sender] > uint32(block.timestamp)) {
            revert ErrorsLib.DebtManager__CoolDownActive();
        }
    }

    /**
    * @dev Check if a token is supported as collateral
    */
    function _isSupportedToken(address token) internal view {
        if (s_supportedCollateral[token] == false) {
            revert ErrorsLib.DebtManager__TokenNotSupported(token);
        }
    }

    /**
    * @dev Revert if amount is zero
    */
    function _moreThanZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert ErrorsLib.DebtManager__NeedsMoreThanZero();
        }
    }

    /**
    * @dev Check if collateral activity is paused for a token
    */
    function _isCollateralPaused(address token) internal view {
        if(token == ETH) {
            revert ErrorsLib.DebtManager__ZeroAddress();
        }
        if (s_collateralPaused[token]) {
            revert ErrorsLib.DebtManager__CollateralActivityPaused(token);
        }
    }


    // External & Public View & Pure Functions

    /**
     * @notice Returns the amount of collateral based on USD value
     * @param collateral: The collateral asset address
     * @param valueOfRepayAmount: The USD value of the amount
     * @return amount: The amount of collateral
     */
    function getCollateralAmount(
        address collateral, 
        uint256 valueOfRepayAmount
    ) public view returns(uint256) {
        return _valueToAmount(collateral, valueOfRepayAmount);
    }

    /**
     * @notice Returns the amount of collateral to seize during liquidation based on USD value
     * @param collateral: The collateral asset address
     * @param valueOfRepayAmount: The USD value of the amount being repaid
     * @return amount: The amount of collateral to seize
     */
    function getCollateralAmountLiquidate(
        address collateral, 
        uint256 valueOfRepayAmount
    ) public view returns(uint256) {
        uint256 liquidationBonus = aave.getAssetLiquidationBonus(collateral);
        uint256 valueOfCollateralToSeize = (valueOfRepayAmount * liquidationBonus) / BASE_PRECISION;
        return _valueToAmount(collateral, valueOfCollateralToSeize);
    }

    /**
     * @notice Returns the maximum collateral withdrawable amount for a user
     * @param user: The address of the user
     * @param collateral: The collateral asset address
     * @return amount: The maximum withdrawable amount of collateral
     */
    function getUserMaxCollateralWithdrawAmount(address user, address collateral) external returns(uint256) {
        _currentPlatformLtvAndLltv();
        
        uint256 _amountCollateral = s_collateralDeposited[user][collateral];
        if(_amountCollateral == 0) {
            revert ErrorsLib.DebtManager__InsufficientCollateral();
        }
        return _maxWithdrawAmount(user, collateral);
    }

    /**
    * @notice Returns whether a token is supported for collateral
    * @param token: The address of the token
    * @return bool: Whether the token is supported
    */
    function checkIfTokenSupported(address token) external view returns (bool) {
        return s_supportedCollateral[token];
    }

    /**
    * @notice Returns whether collateral activity is paused for a token
    * @param token: The address of the token
    * @return bool: Whether collateral activity is paused
    */
    function checkIfCollateralPaused(address token) external view returns (bool) {
        return s_collateralPaused[token];
    }

    /**
     * @notice Returns the maximum borrowable amount and value for a user
     * @param user The address of the user
     * @return value The maximum borrowable value in USD
     * @return amount The maximum borrowable amount in USDC
     */
    function getUserMaxBorrow(address user) external returns(uint256 value, uint256 amount) {
        _currentPlatformLtvAndLltv();

        value = _maxBorrowValue(user);
        amount = _maxBorrowAmount(user);
    }

    /**
     * @notice Returns the user's debt shares in USDC
     * @param user The address of the user
     * @return userAaveDebt The amount of debt owed to Aave
     * @return userTotalDebt The total amount of debt owed to the protocol and Aave (Aave + protocol cut)
     */
    function getUserDebt(address user) external returns (uint256 userAaveDebt, uint256 userTotalDebt) {
        (userAaveDebt, userTotalDebt) = _debtOwed(user);
    }

    /**
     * @notice Returns the platform's total debt in USDC
     * @return aaveDebt: The total debt owed to Aave
     * @return totalDebt: The total debt owed to the protocol and Aave (Aave + protocol cut)
     */
    function getPlatformDebt() external returns(uint256, uint256) {
        _currentPlatformDebt();
        return (aaveDebt, totalDebt);
    }

    /**
     * @notice Returns the protocol revenue accrued
     * @return revenue: The protocol revenue accrued
     */
    function getProtocolRevenue() external view returns(uint256) {
        return s_protocolRevenueAccrued;
    }

    /**
     * @notice Returns the protocol APR markup
     * @return apr: The protocol APR markup
     */
    function getProtocolAPRMarkup() external view returns(uint256) {
        return protocolAPRMarkup;
    }

    /**
     * @notice Returns the liquidation fee
     * @return fee The liquidation fee
     */
    function getLiquidationFee() external view returns(uint256) {
        return s_liquidationFee;
    }

    /**
     * @notice Returns the liquidation bonus
     * @param collateral The collateral asset address
     * @return bonus The liquidation bonus
     */
    function getLiquidationBonus(address collateral) external view returns(uint256 bonus) {
        bonus = aave.getAssetLiquidationBonus(collateral);
        bonus = bonus - BASE_PRECISION; // return only the bonus part
    }

    /**
     * @notice Returns the cool down period
     * @return period: The cool down period in seconds
     */
    function getCoolDownPeriod() external view returns(uint256) {
        return s_coolDownPeriod;
    }

    /**
     * @notice Returns the health factor and status of a user
     * @param user The address of the user
     * @return healthFactor The health factor of the user
     * @return status The health status of the user
     */
    function getUserHealthFactor(address user) external returns (uint256 healthFactor, HealthStatus status) {
        _currentPlatformLtvAndLltv(); // update platform ltv & lltv

        healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            status = HealthStatus.Liquidatable;
        } else if (healthFactor < DANGER_ZONE) {
            status = HealthStatus.Danger;
        } else {
            status = HealthStatus.Healthy;
        }
    }

    /**
     * @notice Returns the total debt to repay for a user in USD value, 1e18 = 1 USD
     * @param user The address of the user
     * @return totalUsdcToRepay The total amount to repay in USDC (Aave debt + protocol cut)
     */
    function getUserTotalDebt(address user) external returns (uint256 totalUsdcToRepay) {
        (, totalUsdcToRepay,) = _getAccountInformation(user);
    }

    /**
     * @notice To be used to check if user is liquidatable externally
     * @notice Returns the user account data including total collateral, total debt, and health factor
     * @param user The address of the user
     * @return _totalCollateral The total collateral value in USD, wad (1e8 = 1 USD)
     * @return _totalDebt The total debt value in USD, wad (1e8 = 1 USD)
     * @return _hFactor The health factor of the user
     */
    function getUserAccountData(address user) external returns (
        uint256 _totalCollateral,
        uint256 _totalDebt,
        uint256 _hFactor
    ) {
        _currentPlatformLtvAndLltv(); // update platform ltv & lltv
        (_totalDebt,, _totalCollateral) = _getAccountInformation(user);
        _totalDebt = _totalDebt * USD_PRECISION / BASE_PRECISION;
        _totalCollateral = _totalCollateral * USD_PRECISION / BASE_PRECISION;
        _hFactor = _calculateHealthFactor(_totalDebt, _totalCollateral);
    }

    /**
     * @notice Returns the USD value of a token amount
     * @param token: The address of the token
     * @param amount: The amount of the token
     * @return value: The USD value of the token amount
     */
    function getUsdValue(address token, uint256 amount) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    /**
     * @notice Returns the price of an asset in USD
     * @param token The address of the token
     * @return price The price of the asset in USD (1e8 = 1 USD)
     */
    function getAssetPrice(address token) external view returns (uint256 price) {
        if (token == ETH) {
            revert ErrorsLib.DebtManager__TokenNotAllowed(token);
        }
        if(s_supportedCollateral[token] == false) {
            revert ErrorsLib.DebtManager__TokenNotSupported(token);
        }
        price = _getAssetPrice(token);
    }

    /**
     * @notice Returns the collateral balance of a user for a specific token
     * @param user: The address of the user
     * @param token: The address of the token
     * @return balance: The collateral balance of the user for the specified token
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     * @notice Returns the total collateral value of a user in USD
     * @param user The address of the user
     * @return totalCollateralValueInUsd The total collateral value of the user in USD
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            if(amount == 0) continue;
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
    }

    /**
     * @dev Based on DebtManager's Aave position
     * @notice Returns the platform LTV and LLTV
     * @return lltv: The platform liquidation loan-to-value ratio (LLTV) in wad (1e18)
     * @return ltv: The platform loan-to-value ratio (LTV) in wad (1e18)
     */
    function getPlatformLltvAndLtv() external returns (uint256, uint256) {
        _currentPlatformLtvAndLltv(); // update platform ltv & lltv
        return (s_platformLltv, s_platformLtv);
    }

    /**
     * @notice Returns an array of collateral tokens
     * @return tokens: The collateral tokens
    */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @notice Returns the total collateral supplied for a specific token
     * @param collateral: The collateral asset address
     * @return totalColSupplied: The total collateral supplied for the specified token
     */
    function getTotalColSupplied(address collateral) external view returns (uint256) {
        return s_totalColSupplied[collateral];
    }

    /**
     * @notice Returns the total debt shares in the protocol
     * @return totalDebtShares: The total debt shares
     */
    function getTotalDebtShares() external view returns (uint256) {
        return s_totalDebtShares;
    }

    /**
     * @notice Returns the user's debt shares in the protocol
     * @param user: The address of the user
     * @return userShares: The user's debt shares
     */
    function getUserShares(address user) external view returns (uint256) {
        return s_userDebtShares[user];
    }

    /**
     * @notice Returns the health factor of a user, internal accounting
     * @param user: The address of the user
     * @return healthFactor: The health factor of the user
     */
    function getHealthFactor(address user) external returns (uint256) {
        return _healthFactor(user);
    }

    /**
    * @notice Returns the next activity timestamp for a user
    * @param user: The address of the user
    * @return timestamp: The next activity timestamp
    */
    function getNextActivity(address user) external view returns (uint32) {
        return s_coolDown[user];
    }

    /**
    * @notice Returns the user's supplied collateral amount
    * @param user The address of the user
    * @return userCollateral The user's supplied collateral amounts
    */
    function getUserSuppliedCollateralAmount( address user ) external view returns (UserCollateral[] memory userCollateral) {
        uint256 len = s_collateralTokens.length;
        userCollateral = new UserCollateral[](len);

        for (uint256 i = 0; i < len; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][tokenAddress];
            if(amount == 0) continue;

            string memory symbol = IERC20Metadata(tokenAddress).symbol();

            userCollateral[i] = UserCollateral({
                token: symbol,
                amount: amount
            });
        }
    }

    /**
     * @notice Returns the liquidation revenue accrued for each collateral token
     * @return liquidationEarnings The liquidation revenue accrued
     */
    function getLiquidationRevenue() external view returns (LiquidationEarnings[] memory liquidationEarnings) {
        uint256 len = s_collateralTokens.length;
        liquidationEarnings = new LiquidationEarnings[](len);

        for (uint256 i = 0; i < len; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_liquidationRevenue[tokenAddress];

            string memory symbol = IERC20Metadata(tokenAddress).symbol();

            liquidationEarnings[i] = LiquidationEarnings({
                token: symbol,
                amount: amount
            });
        }
    }

    /**
     * @notice Returns the liquidation revenue accrued for a specific collateral token
     * @param asset: The collateral asset address
     * @return revenue: The liquidation revenue accrued
     */
    function getLiquidationRevenueSpecific(address asset) external view returns(uint256) {
        return s_liquidationRevenue[asset];
    }
}
