pragma solidity ^0.5.16;

import "./TokenDispenserBase.sol";

contract TokenDispenserI10H60H30 is TokenDispenserBase {
    uint public hour1EndTime;
    uint public hour2EndTime;
    // @notice 10% vested immediately after launch. scaled by 1e18
    uint public constant immediateVestRatio = 1e17;
    // @notice 60% vested lineary in 1st hour. scaled by 1e18
    uint public constant h1VestRatio = 6e17;
    // @notice 30% vested lineary in 2nd hour. scaled by 1e18
    uint public constant h2VestRatio = 3e17;
    // @notice the vest rate in first hour is 0.6 / 1 hour in seconds, scaled by 1e18
    uint public constant h1rate = h1VestRatio / 1 hours;
    // @notice the vest rate in second hour is 0.3 / 1 hour in seconds, scaled by 1e18
    uint public constant h2rate = h2VestRatio / 1 hours;

    constructor (address kine_, uint startTime_) public {
        kine = IERC20(kine_);
        startTime = startTime_;
        transferPaused = false;
        hour1EndTime = startTime_.add(365 days);
        hour2EndTime = startTime_.add(730 days);
    }

    function vestedPerAllocation() public view returns (uint) {
        // vested token per allocation is calculated as
        // Immediately vest 10% after distribution launched
        // Linearly vest 60% in the 1st year after launched
        // Linearly vest 30% in the 2nd year after launched
        uint currentTime = block.timestamp;
        if (currentTime <= startTime) {
            return 0;
        }
        if (currentTime <= hour1EndTime) {
            return immediateVestRatio.add(currentTime.sub(startTime).mul(h1rate));
        }
        if (currentTime <= hour2EndTime) {
            return immediateVestRatio.add(h1VestRatio).add(currentTime.sub(hour1EndTime).mul(h2rate));
        }
        return 1e18;
    }
}