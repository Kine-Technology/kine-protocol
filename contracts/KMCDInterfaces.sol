pragma solidity ^0.5.16;

import "./KineControllerInterface.sol";

contract KMCDStorage {
    /**
     * @dev Guard variable for re-entrancy checks
     */
    bool internal _notEntered;

    /**
    * @notice flag that Kine MCD has been initialized;
    */
    bool public initialized;

    /**
    * @notice Only KUSDMinter can borrow/repay Kine MCD on behalf of users;
    */
    address public minter;

    /**
     * @notice Name for this MCD
     */
    string public name;

    /**
     * @notice Symbol for this MCD
     */
    string public symbol;

    /**
     * @notice Decimals for this MCD
     */
    uint8 public decimals;

    /**
     * @notice Administrator for this contract
     */
    address payable public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address payable public pendingAdmin;

    /**
     * @notice Contract which oversees inter-kToken operations
     */
    KineControllerInterface public controller;

    /**
     * @notice Approved token transfer amounts on behalf of others
     */
    mapping(address => mapping(address => uint)) internal transferAllowances;

    /**
     * @notice Total amount of outstanding borrows of the MCD
     */
    uint public totalBorrows;

    /**
     * @notice Mapping of account addresses to outstanding borrow balances
     */
    mapping(address => uint) internal accountBorrows;
}

contract KMCDInterface is KMCDStorage {
    /**
     * @notice Indicator that this is a KToken contract (for inspection)
     */
    bool public constant isKToken = true;


    /*** Market Events ***/

    /**
     * @notice Event emitted when MCD is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address kTokenCollateral, uint seizeTokens);


    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @notice Event emitted when controller is changed
     */
    event NewController(KineControllerInterface oldController, KineControllerInterface newController);

    /**
     * @notice Event emitted when minter is changed
     */
    event NewMinter(address oldMinter, address newMinter);


    /*** User Interface ***/

    function getAccountSnapshot(address account) external view returns (uint, uint);

    function borrowBalance(address account) public view returns (uint);

    /*** Admin Functions ***/

    function _setPendingAdmin(address payable newPendingAdmin) external;

    function _acceptAdmin() external;

    function _setController(KineControllerInterface newController) public;
}