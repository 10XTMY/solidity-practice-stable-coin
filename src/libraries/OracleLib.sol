//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author 10XTMY
 * @notice This library is used to check Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable by design.
 * We want the DSCEngine to freeze if the prices become stale.
 *
 * So if the Chainlink network explosed and you have a lot of money locked into the protocol.. you're scewed.
 *
 */
library OracleLib {
    error OraceleLib_StalePrice();
    // In production this would be derived from the network
    // We would ask for the heartbeat of the network and use that as the timeout
    // For the purpose of this example, we will use a constant

    uint256 private constant TIMEMOUT = 3 hours;

    // In DSCEngine.sol we can now use this function in place of .lastestRoundData()
    // import OracleLib and declare it in Types section.
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        priceFeed.latestRoundData();
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEMOUT) {
            revert OraceleLib_StalePrice();
        }
        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }
}
