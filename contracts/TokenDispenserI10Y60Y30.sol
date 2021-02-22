pragma solidity ^0.5.16;

import "./TokenDispenserBase.sol";

contract TokenDispenserI10Y60Y30 is TokenDispenserBase {
    uint public year1EndTime;
    uint public year2EndTime;
    // @notice 10% vested immediately after launch. scaled by 1e18
    uint public constant immediateVestRatio = 1e17;
    // @notice 60% vested lineary in 1st year. scaled by 1e18
    uint public constant y1VestRatio = 6e17;
    // @notice 30% vested lineary in 2nd year. scaled by 1e18
    uint public constant y2VestRatio = 3e17;
    // @notice the vest rate in first year is 0.6 / 365 days in seconds, scaled by 1e18
    uint public constant y1rate = y1VestRatio / 365 days;
    // @notice the vest rate in second year is 0.3 / 365 days in seconds, scaled by 1e18
    uint public constant y2rate = y2VestRatio / 365 days;

    constructor (address kine_, uint startTime_) public {
        kine = IERC20(kine_);
        startTime = startTime_;
        transferPaused = false;
        year1EndTime = startTime_.add(365 days);
        year2EndTime = startTime_.add(730 days);
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
        if (currentTime <= year1EndTime) {
            return immediateVestRatio.add(currentTime.sub(startTime).mul(y1rate));
        }
        if (currentTime <= year2EndTime) {
            return immediateVestRatio.add(y1VestRatio).add(currentTime.sub(year1EndTime).mul(y2rate));
        }
        return 1e18;
    }
}