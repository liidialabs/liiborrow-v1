// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// /**
//  * @title MockV3Aggregator
//  * @notice Mock Chainlink Price Feed for testing
//  * @dev Implements AggregatorV3Interface with configurable behavior
//  */
// contract MockV3Aggregator {
//     uint8 public decimals;
//     int256 public latestAnswer;
//     uint256 public latestTimestamp;
//     uint256 public latestRound;

//     mapping(uint256 => int256) public getAnswer;
//     mapping(uint256 => uint256) public getTimestamp;
//     mapping(uint256 => uint256) public getStartedAt;

//     // Control flags for testing
//     bool public shouldRevertOnLatestRoundData;
//     bool public shouldReturnStaleData;
//     uint256 public stalePeriod = 3 hours;

//     constructor(uint8 _decimals, int256 _initialAnswer) {
//         decimals = _decimals;
//         updateAnswer(_initialAnswer);
//     }

//     /**
//      * @notice Update the price
//      */
//     function updateAnswer(int256 _answer) public {
//         latestAnswer = _answer;
//         latestTimestamp = block.timestamp;
//         latestRound++;
//         getAnswer[latestRound] = _answer;
//         getTimestamp[latestRound] = block.timestamp;
//         getStartedAt[latestRound] = block.timestamp;
//     }

//     /**
//      * @notice Update price with custom timestamp
//      */
//     function updateAnswerWithTimestamp(int256 _answer, uint256 _timestamp) external {
//         latestAnswer = _answer;
//         latestTimestamp = _timestamp;
//         latestRound++;
//         getAnswer[latestRound] = _answer;
//         getTimestamp[latestRound] = _timestamp;
//         getStartedAt[latestRound] = _timestamp;
//     }

//     /**
//      * @notice Get latest round data (standard interface)
//      */
//     function latestRoundData()
//         external
//         view
//         returns (
//             uint80 roundId,
//             int256 answer,
//             uint256 startedAt,
//             uint256 updatedAt,
//             uint80 answeredInRound
//         )
//     {
//         require(!shouldRevertOnLatestRoundData, "MockV3Aggregator: reverted");

//         uint256 timestamp = shouldReturnStaleData 
//             ? block.timestamp - stalePeriod - 1 
//             : latestTimestamp;

//         return (
//             uint80(latestRound),
//             latestAnswer,
//             timestamp,
//             timestamp,
//             uint80(latestRound)
//         );
//     }

//     /**
//      * @notice Get data for a specific round
//      */
//     function getRoundData(uint80 _roundId)
//         external
//         view
//         returns (
//             uint80 roundId,
//             int256 answer,
//             uint256 startedAt,
//             uint256 updatedAt,
//             uint80 answeredInRound
//         )
//     {
//         return (
//             _roundId,
//             getAnswer[_roundId],
//             getStartedAt[_roundId],
//             getTimestamp[_roundId],
//             _roundId
//         );
//     }

//     /**
//      * @notice Get description
//      */
//     function description() external pure returns (string memory) {
//         return "MockV3Aggregator";
//     }

//     /**
//      * @notice Get version
//      */
//     function version() external pure returns (uint256) {
//         return 3;
//     }

//     // ============ CONTROL FUNCTIONS FOR TESTING ============

//     /**
//      * @notice Control whether latestRoundData should revert
//      */
//     function setShouldRevertOnLatestRoundData(bool _shouldRevert) external {
//         shouldRevertOnLatestRoundData = _shouldRevert;
//     }

//     /**
//      * @notice Control whether to return stale data
//      */
//     function setShouldReturnStaleData(bool _shouldReturnStale) external {
//         shouldReturnStaleData = _shouldReturnStale;
//     }

//     /**
//      * @notice Set the stale period threshold
//      */
//     function setStalePeriod(uint256 _period) external {
//         stalePeriod = _period;
//     }

//     /**
//      * @notice Reset all flags
//      */
//     function resetFlags() external {
//         shouldRevertOnLatestRoundData = false;
//         shouldReturnStaleData = false;
//         stalePeriod = 3 hours;
//     }

//     // ============ HELPER FUNCTIONS ============

//     /**
//      * @notice Simulate price increase by percentage
//      */
//     function increasePriceByPercent(uint256 percent) external {
//         require(percent <= 1000, "MockV3Aggregator: percent too high"); // Max 1000%
//         int256 increase = (latestAnswer * int256(percent)) / 100;
//         updateAnswer(latestAnswer + increase);
//     }

//     /**
//      * @notice Simulate price decrease by percentage
//      */
//     function decreasePriceByPercent(uint256 percent) external {
//         require(percent <= 100, "MockV3Aggregator: percent too high"); // Max 100%
//         int256 decrease = (latestAnswer * int256(percent)) / 100;
//         updateAnswer(latestAnswer - decrease);
//     }

//     /**
//      * @notice Set negative price (for testing invalid scenarios)
//      */
//     function setNegativePrice() external {
//         updateAnswer(-1);
//     }

//     /**
//      * @notice Set zero price (for testing edge cases)
//      */
//     function setZeroPrice() external {
//         updateAnswer(0);
//     }
// }

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Based on the FluxAggregator contract
 * @notice Use this contract when you need to test
 * other contract's ability to read data from an
 * aggregator contract, but how the aggregator got
 * its answer is unimportant
 */
contract MockV3Aggregator is AggregatorV3Interface {
    uint256 public constant override version = 4;

    uint8 public override decimals;
    int256 public latestAnswer;
    uint256 public latestTimestamp;
    uint256 public latestRound;

    mapping(uint256 => int256) public getAnswer;
    mapping(uint256 => uint256) public getTimestamp;
    mapping(uint256 => uint256) private getStartedAt;
    mapping(uint256 => uint80) private getAnsweredInRound;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        updateAnswer(_initialAnswer);
    }

    function updateAnswer(int256 _answer) public {
        latestAnswer = _answer;
        latestTimestamp = block.timestamp;
        latestRound++;
        getAnswer[latestRound] = _answer;
        getTimestamp[latestRound] = block.timestamp;
        getStartedAt[latestRound] = block.timestamp;
        getAnsweredInRound[latestRound] = uint80(latestRound);
    }

    function updateRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _timestamp,
        uint256 _startedAt
    ) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[_roundId] = _answer;
        getTimestamp[_roundId] = _timestamp;
        getStartedAt[_roundId] = _startedAt;
        getAnsweredInRound[_roundId] = _roundId;
    }

    function updateRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _timestamp,
        uint80 _answeredInRound
    ) public {
        latestRound = _roundId;
        latestAnswer = _answer;
        latestTimestamp = _timestamp;
        getAnswer[_roundId] = _answer;
        getTimestamp[_roundId] = _timestamp;
        getStartedAt[_roundId] = _startedAt;
        getAnsweredInRound[_roundId] = _answeredInRound;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, getAnswer[_roundId], getStartedAt[_roundId], getTimestamp[_roundId], getAnsweredInRound[_roundId]);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(latestRound),
            getAnswer[latestRound],
            getStartedAt[latestRound],
            getTimestamp[latestRound],
            getAnsweredInRound[latestRound]
        );
    }

    function description() external pure override returns (string memory) {
        return "v0.8/tests/MockV3Aggregator.sol";
    }
}