pragma solidity ^0.5.16;

import "./IERC20.sol";

/**
 * @title KineTreasury stores the Kine tokens.
 * @author Kine
 */
contract KineTreasury {
    // @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    // @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

    // @notice Emitted when Kine transferred
    event TransferKine(address indexed target, uint amount);
    
    // @notice Emitted when Kine changed
    event NewKine(address oldKine, address newKine);

    address public admin;
    address public pendingAdmin;
    IERC20 public kine;

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can call");
        _;
    }

    constructor(address admin_, address kine_) public {
        admin = admin_;
        kine = IERC20(kine_);
    }

    // @notice Only admin can transfer kine
    function transferKine(address target, uint amount) external onlyAdmin {
        // check balance;
        uint balance = kine.balanceOf(address(this));
        require(balance >= amount, "not enough kine balance");
        // transfer kine
        bool success = kine.transfer(target, amount);
        require(success, "transfer failed");

        emit TransferKine(target, amount);
    }

    // only admin can set kine
    function _setkine(address newKine) external onlyAdmin {
        address oldKine = address(kine);
        kine = IERC20(newKine);
        emit NewKine(oldKine, newKine);
    }

    /**
      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      */
    function _setPendingAdmin(address newPendingAdmin) external onlyAdmin {
        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      */
    function _acceptAdmin() external {
        require(msg.sender == pendingAdmin && msg.sender != address(0), "unauthorized");

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }
}