pragma solidity ^0.5.16;

import "./KUSDMinter.sol";
import "./KineOracleInterface.sol";
import "./KineControllerInterface.sol";
import "./Ownable.sol";

pragma experimental ABIEncoderV2;

/**
 * @title Kaptain is Kine oracle reporter role and KUSD treasury role at the same time.
 * @author Kine
 */
contract Kaptain is Ownable {
    /// @notice Emitted when oracle changed
    event NewController(address oldController, address newController);
    /// @notice Emitted when kUSD minter changed
    event NewMinter(address oldMinter, address newMinter);

    /// @notice Oracle which gives the price of given asset
    KineControllerInterface public controller;
    /// @notice KUSD minter (see KUSDMinter) only allow treasury to mint/burn KUSD to vault account.
    KUSDMinter public minter;

    constructor (address controller_, address minter_) public {
        controller = KineControllerInterface(controller_);
        minter = KUSDMinter(minter_);
    }

    /// @notice Owner update Kine owned tokens' price and mint/burn kUSD to vault account according to Kine off-chain trading system states.
    function steer(bytes[] calldata messages, bytes[] calldata signatures, string[] calldata symbols, uint256 vaultKusdDelta, bool isVaultIncreased) external onlyOwner {
        KineOracleInterface(controller.getOracle()).postPrices(messages, signatures, symbols);
        if (isVaultIncreased) {
            minter.treasuryMint(vaultKusdDelta);
        } else {
            minter.treasuryBurn(vaultKusdDelta);
        }
    }

    /// @notice Change oracle to new one
    function _setController(address newController) external onlyOwner {
        address oldController = address(controller);
        controller = KineControllerInterface(newController);
        emit NewController(oldController, newController);
    }

    /// @notice Change minter to new one
    function _setMinter(address newMinter) external onlyOwner {
        address oldMinter = address(minter);
        minter = KUSDMinter(newMinter);
        emit NewMinter(oldMinter, newMinter);
    }
}