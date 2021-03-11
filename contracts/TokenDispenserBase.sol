pragma solidity ^0.5.16;

import "./Context.sol";
import "./Math.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract TokenDispenserBase is Context, Ownable {
    using KineSafeMath for uint;
    using SafeERC20 for IERC20;

    event TransferAllocation(address indexed sender, address indexed recipient, uint amount);
    event AddAllocation(address indexed recipient, uint addAllocation, uint newAllocation);
    event ReplaceAllocation(address indexed oldAddress, address indexed newAddress, uint allocation);
    event TransferPaused();
    event TransferUnpaused();
    event AddTransferWhitelist(address account);
    event RemoveTransferWhitelist(address account);

    IERC20 kine;
    uint public startTime;
    uint public vestedPerAllocationStored;
    uint public lastUpdateTime;
    uint public totalAllocation;
    mapping(address => uint) public accountAllocations;

    struct AccountVestedDetail {
        uint vestedPerAllocationUpdated;
        uint accruedVested;
        uint claimed;
    }

    mapping(address => AccountVestedDetail) public accountVestedDetails;
    uint public totalClaimed;

    bool public transferPaused;
    // @dev transfer whitelist maintains a list of accounts that can receive allocations
    // owner transfer isn't limitted by this whitelist
    mapping(address => bool) public transferWhitelist;

    modifier onlyAfterStart() {
        require(block.timestamp >= startTime, "not started yet");
        _;
    }

    modifier onlyInTransferWhitelist(address account) {
        require(transferWhitelist[account], "receipient not in transfer whitelist");
        _;
    }

    modifier updateVested(address account) {
        updateVestedInternal(account);
        _;
    }

    modifier onlyTransferNotPaused() {
        require(!transferPaused, "transfer paused");
        _;
    }

    modifier onlyTransferPaused() {
        require(transferPaused, "transfer not paused");
        _;
    }

    function updateVestedInternal(address account) internal {
        vestedPerAllocationStored = vestedPerAllocation();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            accountVestedDetails[account].accruedVested = vested(account);
            accountVestedDetails[account].vestedPerAllocationUpdated = vestedPerAllocationStored;
        }
    }

    // @dev should be implemented by inheritent contract
    function vestedPerAllocation() public view returns (uint);

    function vested(address account) public view returns (uint) {
        return accountAllocations[account]
        .mul(vestedPerAllocation().sub(accountVestedDetails[account].vestedPerAllocationUpdated))
        .div(1e18)
        .add(accountVestedDetails[account].accruedVested);
    }

    function claimed(address account) public view returns (uint) {
        return accountVestedDetails[account].claimed;
    }

    function claim() external onlyAfterStart updateVested(msg.sender) {
        AccountVestedDetail storage detail = accountVestedDetails[msg.sender];
        uint accruedVested = detail.accruedVested;
        if (accruedVested > 0) {
            detail.claimed = detail.claimed.add(accruedVested);
            totalClaimed = totalClaimed.add(accruedVested);
            detail.accruedVested = 0;
            kine.safeTransfer(msg.sender, accruedVested);
        }
    }

    // @notice User may transfer part or full of its allocations to others.
    // The vested tokens right before transfer belongs to the user account, and the to-be vested tokens will belong to recipient after transfer.
    // Transfer will revert if transfer is paused by owner.
    // Only whitelisted account may transfer their allocations.
    function transferAllocation(address recipient, uint amount) external onlyTransferNotPaused onlyInTransferWhitelist(recipient) updateVested(msg.sender) updateVested(recipient) returns (bool) {
        address payable sender = _msgSender();
        require(sender != address(0), "transfer from the zero address");
        require(recipient != address(0), "transfer to the zero address");

        accountAllocations[sender] = accountAllocations[sender].sub(amount, "transfer amount exceeds balance");
        accountAllocations[recipient] = accountAllocations[recipient].add(amount);
        emit TransferAllocation(sender, recipient, amount);
        return true;
    }

    //////////////////////////////////////////
    // allocation management by owner

    // @notice Only owner may add allocations to accounts.
    // When owner add allocations to recipients after distribution start time, recipients can only recieve partial tokens.
    function addAllocation(address[] calldata recipients, uint[] calldata allocations) external onlyOwner {
        require(recipients.length == allocations.length, "recipients and allocations length not match");
        if (block.timestamp <= startTime) {
            // if distribution has't start, just add allocations to recipients
            for (uint i = 0; i < recipients.length; i++) {
                accountAllocations[recipients[i]] = accountAllocations[recipients[i]].add(allocations[i]);
                totalAllocation = totalAllocation.add(allocations[i]);
                transferWhitelist[recipients[i]] = true;
                emit AddAllocation(recipients[i], allocations[i], accountAllocations[recipients[i]]);
                emit AddTransferWhitelist(recipients[i]);
            }
        } else {
            // if distribution already started, need to update recipients vested allocations before add allocations
            for (uint i = 0; i < recipients.length; i++) {
                updateVestedInternal(recipients[i]);
                accountAllocations[recipients[i]] = accountAllocations[recipients[i]].add(allocations[i]);
                totalAllocation = totalAllocation.add(allocations[i]);
                transferWhitelist[recipients[i]] = true;
                emit AddAllocation(recipients[i], allocations[i], accountAllocations[recipients[i]]);
                emit AddTransferWhitelist(recipients[i]);
            }
        }
    }

    //////////////////////////////////////////////
    // transfer management by owner
    function pauseTransfer() external onlyOwner onlyTransferNotPaused {
        transferPaused = true;
        emit TransferPaused();
    }

    function unpauseTransfer() external onlyOwner onlyTransferPaused {
        transferPaused = false;
        emit TransferUnpaused();
    }

    // @notice Owner is able to transfer allocation between any accounts in case special cases happened, e.g. someone lost their address/key.
    // However, the vested tokens before transfer will remain in the account before transfer.
    // Onwer transfer is not limited by the transfer pause status.
    function transferAllocationFrom(address from, address recipient, uint amount) external onlyOwner updateVested(from) updateVested(recipient) returns (bool) {
        require(from != address(0), "transfer from the zero address");
        require(recipient != address(0), "transfer to the zero address");

        accountAllocations[from] = accountAllocations[from].sub(amount, "transfer amount exceeds balance");
        accountAllocations[recipient] = accountAllocations[recipient].add(amount);
        emit TransferAllocation(from, recipient, amount);
        return true;
    }

    // @notice Owner is able to replace accountVestedDetails address with a new one, in case of receipient give us an unoperateable address (like exchange address)
    // The unclaimed allocations will all be transferred to new address including the vest status.
    function replaceAccountWith(address oldAddress, address newAddress) external onlyOwner {
        require(oldAddress != address(0), "replace from the zero address");
        require(newAddress != address(0), "replace to the zero address");

        uint allocation = accountAllocations[oldAddress];
        AccountVestedDetail memory avd = accountVestedDetails[oldAddress];
        AccountVestedDetail storage navd = accountVestedDetails[newAddress];

        require(accountAllocations[newAddress] == 0, "new address already has allocation");
        require(navd.vestedPerAllocationUpdated == 0, "new address already has vestedPerAllocationUpdated");

        accountAllocations[newAddress] = allocation;
        navd.accruedVested = avd.accruedVested;
        navd.vestedPerAllocationUpdated = avd.vestedPerAllocationUpdated;
        navd.claimed = avd.claimed;

        transferWhitelist[newAddress] = true;

        delete accountAllocations[oldAddress];
        delete accountVestedDetails[oldAddress];
        delete transferWhitelist[oldAddress];

        emit RemoveTransferWhitelist(oldAddress);
        emit AddTransferWhitelist(newAddress);
        emit ReplaceAllocation(oldAddress, newAddress, allocation);
    }

    function addTransferWhitelist(address account) external onlyOwner {
        transferWhitelist[account] = true;
        emit AddTransferWhitelist(account);
    }

    function removeTransferWhitelist(address account) external onlyOwner {
        delete transferWhitelist[account];
        emit RemoveTransferWhitelist(account);
    }
}