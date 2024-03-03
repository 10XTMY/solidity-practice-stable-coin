//SPDX-License-Identifier: MIT
// Handler narrows down the function calls
// lay out conditions for testing
// when using invariant testing

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {ERC20Mock} from "@openzepplin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralisedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    address[] public usersWithCollateral;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscengine, DecentralisedStableCoin _dsc) {
        dsce = _dscengine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDsc(uint256 dscAmount, uint256 addressSeed) public {
        (uint256 totalDscMinted, uint256 collateralValueUsd) = dsce.getAccountInformation(msg.sender);

        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[addressSeed % usersWithCollateral.length];

        // only alowed to mint if the amount is less than the collateral
        int256 maxDscToMint = (int256(collateralValueUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        dscAmount = bound(dscAmount, 0, uint256(maxDscToMint));
        if (dscAmount == 0) {
            return;
        }

        // because the fuzz test will use random addresses
        // we need to ensure we use a user that has deposited collateral
        // we push the user into an array in the deposit function...
        vm.startPrank(sender);
        dsce.mintDsc(dscAmount);
        vm.stopPrank();
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        // we want to use valid collateral to test the deposit function
        // use a seed and amount to generate a valid collateral
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // bound the collateral amount so that it doesn't exceed the maximum deposit size
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        collateral.approve(address(dsce), collateralAmount);

        // this will always break unless we approve the deposit, use prank!
        dsce.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();

        // push the user into the array so we can use them in the mint function
        // caveat: this can double push if the test deposits twice
        usersWithCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        // if there was a bug where a user could redeem more than they have
        // this fuzz test would NOT catch it!
        // this is because we are using the actual balance of the user
        // if we used MAX_DEPOSIT_SIZE instead, we would catch the bug
        // but we would have to set fail_on_revert to false
        // this is why best practice is to have two test folders:
        // continueOnRevert and failOnRevert
        collateralAmount = bound(collateralAmount, 0, maxCollateralToRedeem);
        if (collateralAmount == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), collateralAmount);
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
