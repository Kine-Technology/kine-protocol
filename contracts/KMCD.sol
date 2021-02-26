pragma solidity ^0.5.16;

import "./KineControllerInterface.sol";
import "./KMCDInterfaces.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./KTokenInterfaces.sol";

/**
Copyright 2020 Compound Labs, Inc.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
* Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol
* Modified to work in the Kine system.
* Main modifications:
*   1. removed Comp token related logics.
*   2. removed interest rate model related logics.
*   3. removed mint, redeem logics. users can only supply kTokens (see KToken) and borrow Kine MCD.
*   4. removed transfer logics. MCD can't be transferred.
*   5. removed error code propagation mechanism, using revert to fail fast and loudly.
*/

/**
 * @title Kine's KMCD Contract
 * @notice Kine Market Connected Debt (MCD) contract. Users are allowed to call KUSDMinter to borrow Kine MCD and mint KUSD
 * after they supply collaterals in KTokens. One should notice that Kine MCD is not ERC20 token since it can't be transferred by user.
 * @author Kine
 */
contract KMCD is KMCDInterface, Exponential, KTokenErrorReporter {
    modifier onlyAdmin(){
        require(msg.sender == admin, "only admin can call this function");
        _;
    }

    /// @notice Prevent anyone other than minter from borrow/repay Kine MCD
    modifier onlyMinter {
        require(
            msg.sender == minter,
            "Only minter can call this function."
        );
        _;
    }

    /**
     * @notice Initialize the money market
     * @param controller_ The address of the Controller
     * @param name_ Name of this MCD token
     * @param symbol_ Symbol of this MCD token
     * @param decimals_ Decimal precision of this token
     */
    function initialize(KineControllerInterface controller_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address minter_) public {
        require(msg.sender == admin, "only admin may initialize the market");
        require(initialized == false, "market may only be initialized once");

        // Set the controller
        _setController(controller_);

        minter = minter_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _notEntered = true;
        initialized = true;
    }

    /*** User Interface ***/

    /**
      * @notice Only minter can borrow Kine MCD on behalf of user from the protocol
      * @param borrowAmount Amount of Kine MCD to borrow on behalf of user
      */
    function borrowBehalf(address payable borrower, uint borrowAmount) onlyMinter external {
        borrowInternal(borrower, borrowAmount);
    }

    /**
     * @notice Only minter can repay Kine MCD on behalf of borrower to the protocol
     * @param borrower Account with the MCD being payed off
     * @param repayAmount The amount to repay
     */
    function repayBorrowBehalf(address borrower, uint repayAmount) onlyMinter external {
        repayBorrowBehalfInternal(borrower, repayAmount);
    }

    /**
     * @notice Only minter can liquidates the borrowers collateral on behalf of user
     *  The collateral seized is transferred to the liquidator
     * @param borrower The borrower of MCD to be liquidated
     * @param repayAmount The amount of the MCD to repay
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     */
    function liquidateBorrowBehalf(address liquidator, address borrower, uint repayAmount, KTokenInterface kTokenCollateral) onlyMinter external {
        liquidateBorrowInternal(liquidator, borrower, repayAmount, kTokenCollateral);
    }

    /**
     * @notice Get a snapshot of the account's balances
     * @dev This is used by controller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (token balance, borrow balance)
     */
    function getAccountSnapshot(address account) external view returns (uint, uint) {
        return (0, accountBorrows[account]);
    }

    /**
     * @dev Function to simply retrieve block number
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function getBlockNumber() internal view returns (uint) {
        return block.number;
    }

    /**
     * @notice get account's borrow balance
     * @param account The address whose balance should be get
     * @return The balance
     */
    function borrowBalance(address account) public view returns (uint) {
        return accountBorrows[account];
    }

    /**
      * @notice Sender borrows MCD from the protocol to their own address
      * @param borrowAmount The amount of MCD to borrow
      */
    function borrowInternal(address payable borrower, uint borrowAmount) internal nonReentrant {
        borrowFresh(borrower, borrowAmount);
    }

    struct BorrowLocalVars {
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
    }

    /**
      * @notice Sender borrow MCD from the protocol to their own address
      * @param borrowAmount The amount of the MCD to borrow
      */
    function borrowFresh(address payable borrower, uint borrowAmount) internal {
        /* Fail if borrow not allowed */
        (bool allowed, string memory reason) = controller.borrowAllowed(address(this), borrower, borrowAmount);
        require(allowed, reason);

        BorrowLocalVars memory vars;

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowsNew = accountBorrows + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        vars.accountBorrows = accountBorrows[borrower];

        vars.accountBorrowsNew = vars.accountBorrows.add(borrowAmount, BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED);
        vars.totalBorrowsNew = totalBorrows.add(borrowAmount, BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED);

        /* We write the previously calculated values into storage */
        accountBorrows[borrower] = vars.accountBorrowsNew;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        controller.borrowVerify(address(this), borrower, borrowAmount);
    }

    /**
     * @notice Sender repays MCD belonging to borrower
     * @param borrower the account with the MCD being payed off
     * @param repayAmount The amount to repay
     * @return the actual repayment amount.
     */
    function repayBorrowBehalfInternal(address borrower, uint repayAmount) internal nonReentrant returns (uint) {
        return repayBorrowFresh(msg.sender, borrower, repayAmount);
    }

    struct RepayBorrowLocalVars {
        uint accountBorrows;
        uint accountBorrowsNew;
        uint totalBorrowsNew;
    }

    /**
     * @notice Borrows are repaid by another user, should be the minter.
     * @param payer the account paying off the MCD
     * @param borrower the account with the MCD being payed off
     * @param repayAmount the amount of MCD being returned
     * @return the actual repayment amount.
     */
    function repayBorrowFresh(address payer, address borrower, uint repayAmount) internal returns (uint) {
        /* Fail if repayBorrow not allowed */
        (bool allowed, string memory reason) = controller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);
        require(allowed, reason);

        RepayBorrowLocalVars memory vars;

        /* We fetch the amount the borrower owes */
        vars.accountBorrows = accountBorrows[borrower];

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        vars.accountBorrowsNew = vars.accountBorrows.sub(repayAmount, REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED);
        vars.totalBorrowsNew = totalBorrows.sub(repayAmount, REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED);

        /* We write the previously calculated values into storage */
        accountBorrows[borrower] = vars.accountBorrowsNew;
        totalBorrows = vars.totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(payer, borrower, repayAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

        /* We call the defense hook */
        controller.repayBorrowVerify(address(this), payer, borrower, repayAmount);

        return repayAmount;
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this MCD to be liquidated
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the MCD asset to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowInternal(address liquidator, address borrower, uint repayAmount, KTokenInterface kTokenCollateral) internal nonReentrant returns (uint) {
        return liquidateBorrowFresh(liquidator, borrower, repayAmount, kTokenCollateral);
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this MCD to be liquidated
     * @param liquidator The address repaying the MCD and seizing collateral
     * @param kTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the borrowed MCD to repay
     * @return the actual repayment amount.
     */
    function liquidateBorrowFresh(address liquidator, address borrower, uint repayAmount, KTokenInterface kTokenCollateral) internal returns (uint) {
        /* Revert if trying to seize MCD */
        require(address(kTokenCollateral) != address(this), "Kine MCD can't be seized");

        /* Fail if liquidate not allowed */
        (bool allowed, string memory reason) = controller.liquidateBorrowAllowed(address(this), address(kTokenCollateral), liquidator, borrower, repayAmount);
        require(allowed, reason);

        /* Fail if borrower = liquidator */
        require(borrower != liquidator, INVALID_ACCOUNT_PAIR);

        /* Fail if repayAmount = 0 */
        require(repayAmount != 0, INVALID_CLOSE_AMOUNT_REQUESTED);

        /* Fail if repayAmount = -1 */
        require(repayAmount != uint(- 1), INVALID_CLOSE_AMOUNT_REQUESTED);

        /* Fail if repayBorrow fails */
        uint actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

        /////////////////////////
        // EFFECTS & INTERACTIONS

        /* We calculate the number of collateral tokens that will be seized */
        uint seizeTokens = controller.liquidateCalculateSeizeTokens(address(this), address(kTokenCollateral), actualRepayAmount);

        /* Revert if borrower collateral token balance < seizeTokens */
        require(kTokenCollateral.balanceOf(borrower) >= seizeTokens, LIQUIDATE_SEIZE_TOO_MUCH);

        /* Seize borrower tokens to liquidator */
        kTokenCollateral.seize(liquidator, borrower, seizeTokens);

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(liquidator, borrower, actualRepayAmount, address(kTokenCollateral), seizeTokens);

        /* We call the defense hook */
        controller.liquidateBorrowVerify(address(this), address(kTokenCollateral), liquidator, borrower, actualRepayAmount, seizeTokens);

        return actualRepayAmount;
    }

    /*** Admin Functions ***/

    /**
      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      */
    function _setPendingAdmin(address payable newPendingAdmin) external onlyAdmin() {
        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      * @dev Admin function for pending admin to accept role and update admin
      */
    function _acceptAdmin() external {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
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

    /**
      * @notice Sets a new controller for the market
      * @dev Admin function to set a new controller
      */
    function _setController(KineControllerInterface newController) public onlyAdmin() {
        KineControllerInterface oldController = controller;
        // Ensure invoke controller.isController() returns true
        require(newController.isController(), "marker method returned false");

        // Set market's controller to newController
        controller = newController;

        // Emit NewController(oldController, newController)
        emit NewController(oldController, newController);
    }

    function _setMinter(address newMinter) public onlyAdmin() {
        address oldMinter = minter;
        minter = newMinter;

        emit NewMinter(oldMinter, newMinter);
    }

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true;
        // get a gas-refund post-Istanbul
    }
}
