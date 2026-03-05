// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Patrick Collins, Cyfrin
 * @notice Library for interacting with Chainlink price feeds with staleness checks.
 * @dev Provides utilities to validate price feed data before use in calculations.
 *      Helps prevent reliance on stale or manipulated oracle prices.
 */
library OracleLib {
    /// @notice Thrown when the Chainlink oracle returns stale data.
    /// @dev This can occur if: (1) round ID is zero, (2) answeredInRound < roundId,
    ///      or (3) the time since last update exceeds the timeout.
    error OracleLib__StalePrice();

    /// @notice The maximum acceptable time gap between oracle updates.
    /// @dev If a price feed hasn't been updated within this period, it's considered stale.
    uint256 private constant TIMEOUT = 3 hours;

    /// @notice Fetches the latest round data from a Chainlink oracle and validates it.
    /// @dev Reverts if the price is stale or if the round data is invalid.
    /// @param chainlinkFeed The address of the Chainlink AggregatorV3 price feed.
    /// @return roundId The round ID from the oracle.
    /// @return answer The price answer from the oracle.
    /// @return startedAt The timestamp when the round started.
    /// @return updatedAt The timestamp when the round was last updated.
    /// @return answeredInRound The round ID in which the answer was computed.
    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = chainlinkFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /// @notice Returns the timeout period for oracle price staleness.
    /// @return The timeout in seconds (3 hours).
    function getTimeout() public pure returns (uint256) {
        return TIMEOUT;
    }
}
