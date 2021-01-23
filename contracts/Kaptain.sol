pragma solidity ^0.5.16;

import "./KUSDMinter.sol";
import "./KineOracleInterface.sol";
import "./KineControllerInterface.sol";
import "./Ownable.sol";
import "./KineSafeMath.sol";

pragma experimental ABIEncoderV2;

/**
 * @title Kaptain allows Kine oracle reporter to report Kine token price and balance change of kUSD vault at the same time,
 * meanwhile will calculate the new MCD price according to new kUSD total supply and kMCD total amount.
 * Prices will be post to Kine oracle, and kUSD vault balance change will be submit to kUSD minter.
 * @author Kine
 */
contract Kaptain is Ownable {
    using KineSafeMath for uint;
    /// @notice Emitted when controller changed
    event NewController(address oldController, address newController);
    /// @notice Emitted when kUSD minter changed
    event NewMinter(address oldMinter, address newMinter);
    /// @notice Emitted when kUSD address changed
    event NewKUSD(address oldKUSD, address newKUSD);
    /// @notice Emitted when steered
    event Steer(uint256 scaledMCDPrice, bool isVaultIncreased, uint256 vaultKusdDelta, uint256 reporterNonce);
    /// @notice Emitted when poster changed
    event NewPoster(address oldPoster, address newPoster);

    /// @notice Oracle which gives the price of given asset
    KineControllerInterface public controller;
    /// @notice KUSD minter (see KUSDMinter) only allow treasury to mint/burn KUSD to vault account.
    /// @dev Minter need to set treasury to this Kaptain.
    KUSDMinter public minter;
    /// @notice kUSD address
    IERC20 public kUSD;
    /// @notice Addres of Kine poster
    address public poster;
    /// @notice To prevent replaying reporter signed message and make sure posts are in sequence
    uint public reporterNonce;

    modifier onlyPoster() {
        require(msg.sender == poster, "only poster is allowed");
        _;
    }

    constructor (address controller_, address minter_, address kUSD_, address poster_) public {
        controller = KineControllerInterface(controller_);
        minter = KUSDMinter(minter_);
        kUSD = IERC20(kUSD_);
        poster = poster_;
    }

    /**
     * @notice Owner is Kine oracle prices poster, it post Kine tokens' price and mint/burn kUSD to vault account according to Kine synthetic assets total value states.
     * @param message Signed price data of tokens and kUSD vault balance change
     * @param signature Signature used to recover reporter public key
     */
    function steer(bytes calldata message, bytes calldata signature) external onlyPoster {
        // recover message signer
        address source = source(message, signature);

        // check if signer is Kine oracle reporter
        KineOracleInterface oracle = KineOracleInterface(controller.getOracle());
        require(source == oracle.reporter(), "only accept reporter signed message");

        // decode message
        (bytes[] memory messages, bytes[] memory signatures, string[] memory symbols, uint256 vaultKusdDelta, bool isVaultIncreased, uint256 nonce) = abi.decode(message, (bytes[], bytes[], string[], uint256, bool, uint256));
        // check if nonce is exactly +1, to make sure posts are in sequence
        reporterNonce = reporterNonce.add(1);
        require(reporterNonce == nonce, "bad reporter nonce");

        // call minter to update kUSD total supply
        if (isVaultIncreased) {
            minter.treasuryMint(vaultKusdDelta);
        } else {
            minter.treasuryBurn(vaultKusdDelta);
        }

        // calculate new kMCD price
        uint kMCDTotal = minter.totalStakes();
        uint kUSDTotal = kUSD.totalSupply();

        // kUSD has 18 decimals
        // kMCD has 18 decimals
        // mcdPrice = kUSD total supply / kMCD total amount * 1e6 (scaling factor)
        // if there is no borrowed kMCD, then the kMCD price will be set to inital value 1.
        uint mcdPrice;
        if(kMCDTotal == 0) {
            mcdPrice = 1e6;
        } else {
            mcdPrice = kUSDTotal.mul(1e18).div(kMCDTotal).div(1e12);
        }

        // post kMCD price to oracle, kMCD price will never be guarded by oracle.
        oracle.postMcdPrice(mcdPrice);

        // post Kine token price to oracle
        // @dev it's ok that post Kine price might be guarded.
        oracle.postPrices(messages, signatures, symbols);

        emit Steer(mcdPrice, isVaultIncreased, vaultKusdDelta, reporterNonce);
    }

    /**
     * @notice Recovers the source address which signed a message
     * @dev Comparing to a claimed address would add nothing,
     *  as the caller could simply perform the recover and claim that address.
     * @param message The data that was presumably signed
     * @param signature The fingerprint of the data + private key
     * @return The source address which signed the message, presumably
     */
    function source(bytes memory message, bytes memory signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ecrecover(hash, v, r, s);
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

    /// @notice Change kUSD to new one
    function _setKUSD(address newKUSD) external onlyOwner {
        address oldKUSD = address(kUSD);
        kUSD = IERC20(newKUSD);
        emit NewKUSD(oldKUSD, newKUSD);
    }

    /// @notice Change Poster to new one
    function _setPoster(address newPoster) external onlyOwner {
        address oldPoster = poster;
        poster = newPoster;
        emit NewPoster(oldPoster, newPoster);
    }
}