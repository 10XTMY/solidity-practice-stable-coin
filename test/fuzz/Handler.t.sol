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

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscengine, DecentralisedStableCoin _dsc) {
        dsce = _dscengine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
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
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
