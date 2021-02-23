pragma solidity ^0.5.16;

/**
Copyright 2020 Compound Labs, Inc.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
* Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/ErrorReporter.sol
* Modified to work in the Kine system.
* Main modifications:
*   1. using constant string instead of enums
*/

contract ControllerErrorReporter {
    string internal constant MARKET_NOT_LISTED = "MARKET_NOT_LISTED";
    string internal constant MARKET_ALREADY_LISTED = "MARKET_ALREADY_LISTED";
    string internal constant MARKET_ALREADY_ADDED = "MARKET_ALREADY_ADDED";
    string internal constant EXIT_MARKET_BALANCE_OWED = "EXIT_MARKET_BALANCE_OWED";
    string internal constant EXIT_MARKET_REJECTION = "EXIT_MARKET_REJECTION";
    string internal constant MINT_PAUSED = "MINT_PAUSED";
    string internal constant BORROW_PAUSED = "BORROW_PAUSED";
    string internal constant SEIZE_PAUSED = "SEIZE_PAUSED";
    string internal constant TRANSFER_PAUSED = "TRANSFER_PAUSED";
    string internal constant MARKET_BORROW_CAP_REACHED = "MARKET_BORROW_CAP_REACHED";
    string internal constant MARKET_SUPPLY_CAP_REACHED = "MARKET_SUPPLY_CAP_REACHED";
    string internal constant REDEEM_TOKENS_ZERO = "REDEEM_TOKENS_ZERO";
    string internal constant INSUFFICIENT_LIQUIDITY = "INSUFFICIENT_LIQUIDITY";
    string internal constant INSUFFICIENT_SHORTFALL = "INSUFFICIENT_SHORTFALL";
    string internal constant TOO_MUCH_REPAY = "TOO_MUCH_REPAY";
    string internal constant CONTROLLER_MISMATCH = "CONTROLLER_MISMATCH";
    string internal constant INVALID_COLLATERAL_FACTOR = "INVALID_COLLATERAL_FACTOR";
    string internal constant INVALID_CLOSE_FACTOR = "INVALID_CLOSE_FACTOR";
    string internal constant INVALID_LIQUIDATION_INCENTIVE = "INVALID_LIQUIDATION_INCENTIVE";
}

contract KTokenErrorReporter {
    string internal constant BAD_INPUT = "BAD_INPUT";
    string internal constant TRANSFER_NOT_ALLOWED = "TRANSFER_NOT_ALLOWED";
    string internal constant TRANSFER_NOT_ENOUGH = "TRANSFER_NOT_ENOUGH";
    string internal constant TRANSFER_TOO_MUCH = "TRANSFER_TOO_MUCH";
    string internal constant MINT_NEW_TOTAL_SUPPLY_CALCULATION_FAILED = "MINT_NEW_TOTAL_SUPPLY_CALCULATION_FAILED";
    string internal constant MINT_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED = "MINT_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED";
    string internal constant REDEEM_NEW_TOTAL_SUPPLY_CALCULATION_FAILED = "REDEEM_NEW_TOTAL_SUPPLY_CALCULATION_FAILED";
    string internal constant REDEEM_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED = "REDEEM_NEW_ACCOUNT_BALANCE_CALCULATION_FAILED";
    string internal constant BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED = "BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED";
    string internal constant BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED = "BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED";
    string internal constant REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED = "REPAY_BORROW_NEW_ACCOUNT_BORROW_BALANCE_CALCULATION_FAILED";
    string internal constant REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED = "REPAY_BORROW_NEW_TOTAL_BALANCE_CALCULATION_FAILED";
    string internal constant INVALID_CLOSE_AMOUNT_REQUESTED = "INVALID_CLOSE_AMOUNT_REQUESTED";
    string internal constant LIQUIDATE_SEIZE_TOO_MUCH = "LIQUIDATE_SEIZE_TOO_MUCH";
    string internal constant TOKEN_INSUFFICIENT_CASH = "TOKEN_INSUFFICIENT_CASH";
    string internal constant INVALID_ACCOUNT_PAIR = "INVALID_ACCOUNT_PAIR";
    string internal constant LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED = "LIQUIDATE_SEIZE_BALANCE_DECREMENT_FAILED";
    string internal constant LIQUIDATE_SEIZE_BALANCE_INCREMENT_FAILED = "LIQUIDATE_SEIZE_BALANCE_INCREMENT_FAILED";
    string internal constant TOKEN_TRANSFER_IN_FAILED = "TOKEN_TRANSFER_IN_FAILED";
    string internal constant TOKEN_TRANSFER_IN_OVERFLOW = "TOKEN_TRANSFER_IN_OVERFLOW";
    string internal constant TOKEN_TRANSFER_OUT_FAILED = "TOKEN_TRANSFER_OUT_FAILED";

}