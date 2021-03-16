pragma solidity ^0.5.16;

import "./Ownable.sol";
import "./KineSafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

pragma experimental ABIEncoderV2;

contract RewardClaimer is Ownable {
    using KineSafeMath for uint;
    using SafeERC20 for IERC20;

    event RewardPaid(uint256 indexed id, address indexed to, uint256 rewardAmount);
    event Paused();
    event Unpaused();
    event NewTruthHolder(address oldTruthHolder, address newTruthHolder);
    event TransferErc20(address indexed erc20, address indexed target, uint amount);
    event NewClaimCap(uint oldClaimCap, uint newClaimCap);

    bool public paused;
    IERC20 public kine;
    address public truthHolder;
    mapping(uint => bool) public claimHistory;
    uint public claimCap;

    constructor (address kine_, address truthHolder_, uint claimCap_) public {
        paused = false;
        kine = IERC20(kine_);
        truthHolder = truthHolder_;
        claimCap = claimCap_;
    }

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    function claim(bytes calldata message, bytes calldata signature) external notPaused {
        address source = source(message, signature);
        require(source == truthHolder, "only accept truthHolder signed message");

        (uint256 id, address to, uint256 reward) = abi.decode(message, (uint256, address, uint256));
        require(!claimHistory[id], "already claimed");
        require(reward < claimCap, "reached claimCap limit");

        claimHistory[id] = true;
        kine.safeTransfer(to, reward);
        emit RewardPaid(id, to, reward);
    }

    function source(bytes memory message, bytes memory signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ecrecover(hash, v, r, s);
    }

    function _pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function _unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function _changeTruthHolder(address newTruthHolder) external onlyOwner {
        address oldHolder = truthHolder;
        truthHolder = newTruthHolder;
        emit NewTruthHolder(oldHolder, newTruthHolder);
    }

    function _changeClaimCap(uint newClaimCap) external onlyOwner {
        uint oldCap = claimCap;
        claimCap = newClaimCap;
        emit NewClaimCap(oldCap, newClaimCap);
    }

    function transferErc20(address erc20Addr, address target, uint amount) external onlyOwner {
        IERC20 erc20 = IERC20(erc20Addr);
        uint balance = erc20.balanceOf(address(this));
        require(balance >= amount, "not enough erc20 balance");
        erc20.safeTransfer(target, amount);
        emit TransferErc20(erc20Addr, target, amount);
    }
}