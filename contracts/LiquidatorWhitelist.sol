pragma solidity ^0.5.16;

import "./Ownable.sol";

/**
 * @title LiquidatorWhitelist
 * @author Kine
 */
contract LiquidatorWhitelist is Ownable {
    /// @notice liquidator list, use mapping combined with list, to save gas and also track whole whitelist
    mapping(address => bool) public liquidators;
    address[] public whitelist;

    event LiquidatorAdded(address newLiquidator);

    event LiquidatorRemoved(address liquidatorRemoved);

    /// @notice check if valid liquidator
    function isListed(address liquidatorToVerify) external view returns (bool){
        return liquidators[liquidatorToVerify];
    }

    /// @notice get the whole whitelist
    function getWhitelist() public view returns (address[] memory) {
        return whitelist;
    }

    function addLiquidators(address[] memory liquidatorsToAdd) public {
        for(uint i = 0; i < liquidatorsToAdd.length; i++){
            address liquidatorToAdd = liquidatorsToAdd[i];
            require(liquidators[liquidatorToAdd] == false, "existed");
            liquidators[liquidatorToAdd] = true;
            whitelist.push(liquidatorToAdd);
            emit LiquidatorAdded(liquidatorToAdd);
        }
    }

    function removeLiquidator(address liquidatorToRemove) public {
        require(liquidators[liquidatorToRemove], "not existed");

        // remove mapping item
        delete liquidators[liquidatorToRemove];

        // remove in whitelist
        for(uint i = 0; i < whitelist.length; i++){
            if(whitelist[i] == liquidatorToRemove){
                whitelist[i] = whitelist[whitelist.length - 1];
                whitelist.pop();
                break;
            }
        }

        emit LiquidatorRemoved(liquidatorToRemove);
    }
}