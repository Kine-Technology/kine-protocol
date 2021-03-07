pragma solidity ^0.5.16;

import "./TokenDispenserBase.sol";

contract TokenDispenserI25H75 is TokenDispenserBase {
    uint public year1EndTime;
    // @notice 25% vested immediately after launch. scaled by 1e18
    uint public constant immediateVestRatio = 25e16;
    // @notice 75% vested lineary in 1st year. scaled by 1e18
    uint public constant y1VestRatio = 75e16;
    // @notice the vest rate in first year is 0.75 / 365 days in seconds, scaled by 1e18
    uint public constant y1rate = y1VestRatio / 10 minutes;

    constructor (address kine_, uint startTime_) public {
        kine = IERC20(kine_);
        startTime = startTime_;
        transferPaused = false;
        year1EndTime = startTime_.add(10 minutes);
    }

    function vestedPerAllocation() public view returns (uint) {
        // vested token per allocation is calculated as
        // Immediately vest 25% after distribution launched
        // Linearly vest 75% in the 1st year after launched
        uint currentTime = block.timestamp;
        if (currentTime <= startTime) {
            return 0;
        }
        if (currentTime <= year1EndTime) {
            return immediateVestRatio.add(currentTime.sub(startTime).mul(y1rate));
        }
        return 1e18;
    }
}