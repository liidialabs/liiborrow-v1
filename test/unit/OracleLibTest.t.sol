// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.20;

// import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
// import { Test, console } from "forge-std/Test.sol";
// import { StdCheats } from "forge-std/StdCheats.sol";
// import { OracleLib, AggregatorV3Interface } from "../../src/libraries/OracleLib.sol";

// contract OracleLibTest is StdCheats, Test {
//     using OracleLib for AggregatorV3Interface;

//     MockV3Aggregator public wbtcPriceFeed;
//     AggregatorV3Interface priceFeed;
//     uint8 public constant DECIMALS = 8;
//     int256 public constant INITIAL_PRICE = 2000 ether;

//     function setUp() public {
//         wbtcPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
//         priceFeed = AggregatorV3Interface(wbtcPriceFeed);
//     }

//     function testGetTimeout() public view {
//         uint256 expectedTimeout = 3 hours;
//         assertEq(OracleLib.getTimeout(), expectedTimeout);
//     }

//     /**
//      * @notice Tests that the function reverts when price data is stale (older than TIMEOUT)
//      */
//     function testPriceRevertsOnStaleCheck() public {
//         // Move time forward beyond the timeout period (3 hours)
//         vm.warp(block.timestamp + 4 hours + 1 seconds);
//         vm.roll(block.number + 1);

//         vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
//         OracleLib.staleCheckLatestRoundData(priceFeed);
//     }

//     /**
//      * @notice Tests that the function reverts when answeredInRound < roundId
//      * This indicates the round is not fully propagated across the oracle network
//      */
//     function testPriceRevertsOnBadAnsweredInRound() public {
//         uint80 roundId = 5;
//         uint80 answeredInRound = 3; // Less than roundId - indicates stale data
        
//         // Use the 5-parameter version of updateRoundData to set answeredInRound < roundId
//         wbtcPriceFeed.updateRoundData(
//             roundId,              // roundId
//             INITIAL_PRICE,        // answer
//             block.timestamp,      // startedAt
//             block.timestamp,      // updatedAt
//             answeredInRound       // answeredInRound (less than roundId)
//         );

//         vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
//         OracleLib.staleCheckLatestRoundData(priceFeed);
//     }

//     /**
//      * @notice Tests that the function reverts when updatedAt is 0
//      * This indicates the round has never been updated
//      */
//     function testPriceRevertsOnZeroUpdatedAt() public {
//         wbtcPriceFeed.updateRoundData(
//             2,                // roundId
//             INITIAL_PRICE,    // answer
//             block.timestamp,  // startedAt
//             0,                // updatedAt = 0 (triggers the revert)
//             2                 // answeredInRound
//         );

//         vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
//         OracleLib.staleCheckLatestRoundData(priceFeed);
//     }

//     /**
//      * @notice Tests successful price retrieval with fresh, valid data
//      */
//     function testSuccessfulPriceRetrieval() public view {
//         (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
//             OracleLib.staleCheckLatestRoundData(priceFeed);
        
//         // Verify all return values are valid
//         assertGt(roundId, 0, "Round ID should be greater than 0");
//         assertEq(answer, INITIAL_PRICE, "Answer should match initial price");
//         assertGt(updatedAt, 0, "Updated timestamp should be greater than 0");
//         assertEq(answeredInRound, roundId, "AnsweredInRound should equal roundId");
//         assertGt(startedAt, 0, "Started timestamp should be greater than 0");
//     }

//     /**
//      * @notice Tests that price check succeeds right at the timeout boundary
//      */
//     function testPriceAtTimeoutBoundary() public {
//         // Move time forward to exactly 3 hours (should still pass)
//         vm.warp(block.timestamp + 3 hours);

//         // This should NOT revert
//         (uint80 roundId, int256 answer,,,) = OracleLib.staleCheckLatestRoundData(priceFeed);
        
//         assertEq(answer, INITIAL_PRICE);
//     }

//     /**
//      * @notice Tests that price check fails just past the timeout boundary
//      */
//     function testPriceJustPastTimeoutBoundary() public {
//         // Move time forward to 3 hours + 1 second (should fail)
//         vm.warp(block.timestamp + 3 hours + 1 seconds);

//         vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
//         OracleLib.staleCheckLatestRoundData(priceFeed);
//     }
// }