// SPDX-License-Identifier: MIT

// Invariant/Fuzz Testing
// contains properties that should always hold

// what are our invariants?
// 1. The total supply of DSC should be less than total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant
// only focusing on these two for now

// Further Reading:
// see https://book.getfoundry.sh/forge/invariant-testing

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzepplin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValye = dsce.getUsdValue(wbtc, totalBtcDeposited);

        // bug here, if the price spikes drops suddenly, our system crashes
        // a huge drop say to 50% in one block would break the system
        // this was discovered in the fuzz/invariant price feed tests
        assert(wethValue + wbtcValye >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        // we can call any getter function here
        // and assert that it does not revert
        // in terminal use:
        // forge inspect <contractName> methods
        // eg. forge inspect DSCEngine methods
        // this displays all the methods in the contract
        dsce.getLiquidationBonus();
        dsce.getPrecision();
    }
}
