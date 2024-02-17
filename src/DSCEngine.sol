// SPDX-License-Identifier: MIT

// Layout of Contract:
// pragma statements
// imports
// interfaces
// libraries
// contracts
// Errors

// inside each contract, library, or interface:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzepplin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzepplin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author 10XTMY
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1:1 USD peg.
 * This stablecoin has the following properties:
 * - Exogenous Collateral: ETH, BTC
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralised". At no point should the value of all collateral be <= the $ backed value of all DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all of the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 *
 */

// usually we would create an interface with all the functions
// but for this project they will be declared below
contract DSCEngine is ReentrancyGuard {
    ///////////////
    // Errors   //
    /////////////
    error DSCEngine__ZeroDeposit();
    error DSCEngine__ZeroWithdraw();
    error DSCEngine__ZeroMintAmount();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__AlreadyDeposited();

    ////////////////////////
    // State Variables   //
    //////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralised
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidators
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1:1 is the minimum health factor
    // token address to price feed address
    mapping(address token => address priceFeed) private s_priceFeeds;
    // map users balances to a mapping of tokens to amounts
    // this helps us keep track of how much collateral each user has
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    DecentralisedStableCoin private immutable i_dsc;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    ///////////////
    // Events   //
    /////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    ///////////////////
    // Modifiers    //
    /////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////////////////
    // External Functions   //
    /////////////////////////

    /*
    * @notice follows CEI pattern (Check-Effect-Interact)
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @param amountDscToMint The amount of DSC to mint
    * @notice this function will deposit collateral and mint dsc in one transaction
    */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern (Check-Effect-Interact)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        // checks
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant // re-entrancies are one of the most common attack vectors
    // get nonReentrant from OpenZeppelin ReentrancyGuard
    // when working with external contracts, always use nonReentrant
    // nonReentrant costs a bit more gas but much more secure
    {
        // effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // when updating state, emit an event
        // this is a good practice to help users and other contracts know what is happening
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // interactions
        // transfer the collateral from the user to this contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // DRY: Don't Repeat Yourself
    // in order to redeem collateral
    // 1. health factor must be over 1 AFTER collateral pulled
    // $100 ETH -> $20 DSC
    // This will break the health factor
    // Must burn DSC and redeem ETH
    // So we combine the two functions into one
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);

        // doing the check last to save gas
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // $100 ETH <- overcollateralised, but what if price of ETH tanks to $40? -> Liquidation!
    // set a threshold for liquidation, e.g. 150% collateralisation ($75 in the case of DSC being $50)
    // $50 DSC

    // if the threshold is breached, the system will liquidate the collateral
    // If someone pays back your minted DSC, they can have all of your
    // collateral at a discount.

    // USER_A
    // $100 ETH -> $74
    // $50 DSC
    // UDNERCOLLATERALISED

    // USER_B
    // I'll pay back the $50 DSC, and take all of your collateral
    // So for paying $50 DSC, I get $74 worth of ETH.
    // I just made $24 profit.
    // USER_A is now COLLATERALISED, no debt, no DSC, no ETH. Zeroed out.

    // Insentivises people to keep the system overcollateralised.

    /**
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice this function burns DSC then redeems collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral will check the health factor
    }

    /**
     * @notice follows CEI pattern (Check-Effect-Interact)
     * @param amountDSCToMint The amount of DSC to mint
     * @notice they must have more than collateral value of than the minimum threshold
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDSCToMint;
        // if they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // burning debt so no need to check health factor
    // but for now we will include it, decide in gas audit if we want to keep it
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // doubt this would ever occur
    }

    /**
     *
     * @notice Follows CEI pattern (Check-Effect-Interact)
     * @param collateral The ERC20 token address of the collateral to liquidate
     * @param user The user to liquidate. Their health factor must be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC to burn in order to improve the health factor of the user
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the user's funds.
     * @notice This function assumes the protocol will be roughly 200% overcollateralised.
     * @notice A known bug would be if the protocl were 100% or less collateralised, then we would not be able to insentivise the liquidators.
     *
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // check health factor
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // burn the DSC "debt"
        // take their collateral
        // bad user: $140 ETH, $100 DSC. Liquidation threshold is 150%
        // $140 * 150% = $210
        // debt to cover = $100
        // $100 DSC == ??? ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // TODO: For real world applications:
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury

        // Give the liquidator a 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // Redeem the collateral
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        // Burn the DSC
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);

        // Check the health factor of the liquidatee
        if (endingHealthFactor >= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // Check the health factor of the liquidator
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    //////////////////////////
    // Public Functions    //
    ////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedaddresses, address dscAddress) {
        // USD Price Feeds (BTC/USD, ETH/USD, etc.)
        if (tokenAddresses.length != priceFeedaddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // map the token to the price feed
            s_priceFeeds[tokenAddresses[i]] = priceFeedaddresses[i];
            // add the token to the list of collateral tokens
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ///////////////////////////////////////////
    // Private & Internal View Functions    //
    /////////////////////////////////////////

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
        moreThanZero(amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev Low-Level internal function, do not call unless the function calling it is
     * checking the health factor of the user
     */
    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collaterlValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collaterlValueInUsd = getAccountCollateralValueInUsd(user);
    }
    /**
     * Returns how close to liquidation the user is
     * If the health factor is less than 1, the user is undercollateralised, the user can be liquidated
     * @param user The address of the user to check the health factor of
     */

    function _healthFactor(address user) private view returns (uint256) {
        // 1. Get the value of all collateral
        // 2. Get the value of all DSC minted
        // 3. Return the ratio
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        // return collateralValueInUsd / totalDSCMinted; <-- (100 / 100) is 1:1, but we want 1.5:1 (liquidation threshold)
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // 1000 ETH * 50 = 50,000 /100 = 500 / 100 = 5 (>=1)
        // $150 ETH / $100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = 75 / 100 = 0.75 (<1)
        // 50% liquidation threshold means you have to have 200% collateralisation

        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health factor (do they have enough collateral?)
        // 2. If not, revert
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    ///////////////////////////////////////
    // Public & External View Functions //
    /////////////////////////////////////

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getTokenAmountFromUsd(address token, uint256 amountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1ETH = $2,000
        // ($10e18 * 1e18) / (2000 * 1e10) = 5e18
        // 0.005000000000000000 <- How much ETH you get for $10 of debt (10/2000 = 0.005)
        return ((amountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through all the tokens the user has deposited
        // map it to the price feed to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1ETH = $1,000
        // The returned value from CL will be 1000 * 1e8 (ETH USD has 8 decimal places)
        // return price * amount; <-- ths will overflow (wei conversion eg:
        // (1000 * 1e8 * 1e10) * 1000 * 1e18)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collaterlValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
