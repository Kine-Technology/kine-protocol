pragma solidity ^0.5.16;

import "./KToken.sol";
import "./KMCD.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./KineControllerInterface.sol";
import "./ControllerStorage.sol";
import "./Unitroller.sol";
import "./KineOracleInterface.sol";
import "./KineSafeMath.sol";

/**
Copyright 2020 Compound Labs, Inc.
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
* Original work from Compound: https://github.com/compound-finance/compound-protocol/blob/master/contracts/Comptroller.sol
* Modified to work in the Kine system.
* Main modifications:
*   1. removed Comp token related logics.
*   2. removed interest rate model related logics.
*   3. simplified calculations in mint, redeem, liquidity check, seize due to we don't use interest model/exchange rate.
*   4. user can only supply kTokens (see KToken) and borrow Kine MCDs (see KMCD). Kine MCD's underlying can be considered as itself.
*   5. removed error code propagation mechanism, using revert to fail fast and loudly.
*/

/**
 * @title Kine's Controller Contract
 * @author Kine
 */
contract Controller is ControllerStorage, KineControllerInterface, Exponential, ControllerErrorReporter {
    /// @notice Emitted when an admin supports a market
    event MarketListed(KToken kToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(KToken kToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(KToken kToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(KToken kToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(KineOracleInterface oldPriceOracle, KineOracleInterface newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(KToken kToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a kToken is changed
    event NewBorrowCap(KToken indexed kToken, uint newBorrowCap);

    /// @notice Emitted when supply cap for a kToken is changed
    event NewSupplyCap(KToken indexed kToken, uint newSupplyCap);

    /// @notice Emitted when borrow/supply cap guardian is changed
    event NewCapGuardian(address oldCapGuardian, address newCapGuardian);

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // liquidationIncentiveMantissa must be no less than this value
    uint internal constant liquidationIncentiveMinMantissa = 1.0e18; // 1.0

    // liquidationIncentiveMantissa must be no greater than this value
    uint internal constant liquidationIncentiveMaxMantissa = 1.5e18; // 1.5

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can call this function");
        _;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (KToken[] memory) {
        KToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param kToken The kToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, KToken kToken) external view returns (bool) {
        return markets[address(kToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param kTokens The list of addresses of the kToken markets to be enabled
     * @dev will revert if any market entering failed
     */
    function enterMarkets(address[] memory kTokens) public {
        uint len = kTokens.length;
        for (uint i = 0; i < len; i++) {
            KToken kToken = KToken(kTokens[i]);
            addToMarketInternal(kToken, msg.sender);
        }
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param kToken The market to enter
     * @param borrower The address of the account to modify
     */
    function addToMarketInternal(KToken kToken, address borrower) internal {
        Market storage marketToJoin = markets[address(kToken)];

        require(marketToJoin.isListed, MARKET_NOT_LISTED);

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(kToken);

        emit MarketEntered(kToken, borrower);
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param kTokenAddress The address of the asset to be removed
     */
    function exitMarket(address kTokenAddress) external {
        KToken kToken = KToken(kTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the kToken */
        (uint tokensHeld, uint amountOwed) = kToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        require(amountOwed == 0, EXIT_MARKET_BALANCE_OWED);

        /* Fail if the sender is not permitted to redeem all of their tokens */
        (bool allowed,) = redeemAllowedInternal(kTokenAddress, msg.sender, tokensHeld);
        require(allowed, EXIT_MARKET_REJECTION);

        Market storage marketToExit = markets[address(kToken)];

        /* Succeed true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return;
        }

        /* Set kToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete kToken from the account’s list of assets */
        // load into memory for faster iteration
        KToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == kToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        require(assetIndex < len, "accountAssets array broken");

        // copy last item in list to location of item to be removed, reduce length by 1
        KToken[] storage storedList = accountAssets[msg.sender];
        if (assetIndex != storedList.length - 1) {
            storedList[assetIndex] = storedList[storedList.length - 1];
        }
        storedList.length--;

        emit MarketExited(kToken, msg.sender);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param kToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return false and reason if mint not allowed, otherwise return true and empty string
     */
    function mintAllowed(address kToken, address minter, uint mintAmount) external returns (bool allowed, string memory reason) {
        if (mintGuardianPaused[kToken]) {
            allowed = false;
            reason = MINT_PAUSED;
            return (allowed, reason);
        }

        uint supplyCap = supplyCaps[kToken];
        // Supply cap of 0 corresponds to unlimited supplying
        if (supplyCap != 0) {
            uint totalSupply = KToken(kToken).totalSupply();
            uint nextTotalSupply = totalSupply.add(mintAmount);
            if (nextTotalSupply > supplyCap) {
                allowed = false;
                reason = MARKET_SUPPLY_CAP_REACHED;
                return (allowed, reason);
            }
        }

        // Shh - currently unused
        minter;

        if (!markets[kToken].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
            return (allowed, reason);
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param kToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address kToken, address minter, uint actualMintAmount, uint mintTokens) external {
        // Shh - currently unused
        kToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param kToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of kTokens to exchange for the underlying asset in the market
     * @return false and reason if redeem not allowed, otherwise return true and empty string
     */
    function redeemAllowed(address kToken, address redeemer, uint redeemTokens) external returns (bool allowed, string memory reason) {
        return redeemAllowedInternal(kToken, redeemer, redeemTokens);
    }

    /**
     * @param kToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of kTokens to exchange for the underlying asset in the market
     * @return false and reason if redeem not allowed, otherwise return true and empty string
     */
    function redeemAllowedInternal(address kToken, address redeemer, uint redeemTokens) internal view returns (bool allowed, string memory reason) {
        if (!markets[kToken].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
            return (allowed, reason);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[kToken].accountMembership[redeemer]) {
            allowed = true;
            return (allowed, reason);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, KToken(kToken), redeemTokens, 0);
        if (shortfall > 0) {
            allowed = false;
            reason = INSUFFICIENT_LIQUIDITY;
            return (allowed, reason);
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param kToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address kToken, address redeemer, uint redeemTokens) external {
        // Shh - currently unused
        kToken;
        redeemer;

        require(redeemTokens != 0, REDEEM_TOKENS_ZERO);
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param kToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return false and reason if borrow not allowed, otherwise return true and empty string
     */
    function borrowAllowed(address kToken, address borrower, uint borrowAmount) external returns (bool allowed, string memory reason) {
        if (borrowGuardianPaused[kToken]) {
            allowed = false;
            reason = BORROW_PAUSED;
            return (allowed, reason);
        }

        if (!markets[kToken].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
            return (allowed, reason);
        }

        if (!markets[kToken].accountMembership[borrower]) {
            // only kTokens may call borrowAllowed if borrower not in market
            require(msg.sender == kToken, "sender must be kToken");

            // attempt to add borrower to the market
            addToMarketInternal(KToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(markets[kToken].accountMembership[borrower]);
        }

        require(oracle.getUnderlyingPrice(kToken) != 0, "price error");

        uint borrowCap = borrowCaps[kToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = KMCD(kToken).totalBorrows();
            uint nextTotalBorrows = totalBorrows.add(borrowAmount);
            if (nextTotalBorrows > borrowCap) {
                allowed = false;
                reason = MARKET_BORROW_CAP_REACHED;
                return (allowed, reason);
            }
        }

        (, uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, KToken(kToken), 0, borrowAmount);
        if (shortfall > 0) {
            allowed = false;
            reason = INSUFFICIENT_LIQUIDITY;
            return (allowed, reason);
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param kToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address kToken, address borrower, uint borrowAmount) external {
        // Shh - currently unused
        kToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param kToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return false and reason if repay borrow not allowed, otherwise return true and empty string
     */
    function repayBorrowAllowed(
        address kToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (bool allowed, string memory reason) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[kToken].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param kToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address kToken,
        address payer,
        address borrower,
        uint actualRepayAmount) external {
        // Shh - currently unused
        kToken;
        payer;
        borrower;
        actualRepayAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @return false and reason if liquidate borrow not allowed, otherwise return true and empty string
     */
    function liquidateBorrowAllowed(
        address kTokenBorrowed,
        address kTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (bool allowed, string memory reason) {
        // Shh - currently unused
        liquidator;

        if (!markets[kTokenBorrowed].isListed || !markets[kTokenCollateral].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
            return (allowed, reason);
        }

        if (KToken(kTokenCollateral).controller() != KToken(kTokenBorrowed).controller()) {
            allowed = false;
            reason = CONTROLLER_MISMATCH;
            return (allowed, reason);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (, uint shortfall) = getAccountLiquidityInternal(borrower);
        if (shortfall == 0) {
            allowed = false;
            reason = INSUFFICIENT_SHORTFALL;
            return (allowed, reason);
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        /* Only KMCD has borrow related logics */
        uint borrowBalance = KMCD(kTokenBorrowed).borrowBalance(borrower);
        uint maxClose = mulScalarTruncate(Exp({mantissa : closeFactorMantissa}), borrowBalance);
        if (repayAmount > maxClose) {
            allowed = false;
            reason = TOO_MUCH_REPAY;
            return (allowed, reason);
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address kTokenBorrowed,
        address kTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens) external {
        // Shh - currently unused
        kTokenBorrowed;
        kTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     * @return false and reason if seize not allowed, otherwise return true and empty string
     */
    function seizeAllowed(
        address kTokenCollateral,
        address kTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (bool allowed, string memory reason) {
        if (seizeGuardianPaused) {
            allowed = false;
            reason = SEIZE_PAUSED;
            return (allowed, reason);
        }

        // Shh - currently unused
        seizeTokens;
        liquidator;
        borrower;

        if (!markets[kTokenCollateral].isListed || !markets[kTokenBorrowed].isListed) {
            allowed = false;
            reason = MARKET_NOT_LISTED;
            return (allowed, reason);
        }

        if (KToken(kTokenCollateral).controller() != KToken(kTokenBorrowed).controller()) {
            allowed = false;
            reason = CONTROLLER_MISMATCH;
            return (allowed, reason);
        }

        allowed = true;
        return (allowed, reason);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param kTokenCollateral Asset which was used as collateral and will be seized
     * @param kTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address kTokenCollateral,
        address kTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external {
        // Shh - currently unused
        kTokenCollateral;
        kTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param kToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of kTokens to transfer
     * @return false and reason if seize not allowed, otherwise return true and empty string
     */
    function transferAllowed(address kToken, address src, address dst, uint transferTokens) external returns (bool allowed, string memory reason) {
        if (transferGuardianPaused) {
            allowed = false;
            reason = TRANSFER_PAUSED;
            return (allowed, reason);
        }

        // not used currently
        dst;

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        return redeemAllowedInternal(kToken, src, transferTokens);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param kToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of kTokens to transfer
     */
    function transferVerify(address kToken, address src, address dst, uint transferTokens) external {
        // Shh - currently unused
        kToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `kTokenBalance` is the number of kTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     *  In Kine system, user can only borrow Kine MCD, the `borrowBalance` is the amount of Kine MCD account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint kTokenBalance;
        uint borrowBalance;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, KToken(0), 0, 0);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, KToken(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param kTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address kTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, KToken(kTokenModify), redeemTokens, borrowAmount);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param kTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        KToken kTokenModify,
        uint redeemTokens,
        uint borrowAmount) internal view returns (uint, uint) {

        AccountLiquidityLocalVars memory vars;

        // For each asset the account is in
        KToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            KToken asset = assets[i];

            // Read the balances from the kToken
            (vars.kTokenBalance, vars.borrowBalance) = asset.getAccountSnapshot(account);
            vars.collateralFactor = Exp({mantissa : markets[address(asset)].collateralFactorMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(address(asset));
            require(vars.oraclePriceMantissa != 0, "price error");
            vars.oraclePrice = Exp({mantissa : vars.oraclePriceMantissa});

            // Pre-compute a conversion factor
            vars.tokensToDenom = mulExp(vars.collateralFactor, vars.oraclePrice);

            // sumCollateral += tokensToDenom * kTokenBalance
            vars.sumCollateral = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.kTokenBalance, vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = mulScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with kTokenModify
            if (asset == kTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mulScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mulScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in kMCD.liquidateBorrowFresh)
     * @param kTokenBorrowed The address of the borrowed kToken
     * @param kTokenCollateral The address of the collateral kToken
     * @param actualRepayAmount The amount of kTokenBorrowed underlying to convert into kTokenCollateral tokens
     * @return number of kTokenCollateral tokens to be seized in a liquidation
     */
    function liquidateCalculateSeizeTokens(address kTokenBorrowed, address kTokenCollateral, uint actualRepayAmount) external view returns (uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(kTokenBorrowed);
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(kTokenCollateral);
        require(priceBorrowedMantissa != 0 && priceCollateralMantissa != 0, "price error");

        /*
         *  calculate the number of collateral tokens to seize:
         *  seizeTokens = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
        */
        Exp memory numerator = mulExp(liquidationIncentiveMantissa, priceBorrowedMantissa);
        Exp memory denominator = Exp({mantissa : priceCollateralMantissa});
        Exp memory ratio = divExp(numerator, denominator);
        uint seizeTokens = mulScalarTruncate(ratio, actualRepayAmount);

        return seizeTokens;
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the controller
      * @dev Admin function to set a new price oracle
      */
    function _setPriceOracle(KineOracleInterface newOracle) external onlyAdmin() {
        KineOracleInterface oldOracle = oracle;
        oracle = newOracle;
        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      */
    function _setCloseFactor(uint newCloseFactorMantissa) external onlyAdmin() {
        require(newCloseFactorMantissa <= closeFactorMaxMantissa, INVALID_CLOSE_FACTOR);
        require(newCloseFactorMantissa >= closeFactorMinMantissa, INVALID_CLOSE_FACTOR);

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param kToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      */
    function _setCollateralFactor(KToken kToken, uint newCollateralFactorMantissa) external onlyAdmin() {
        // Verify market is listed
        Market storage market = markets[address(kToken)];
        require(market.isListed, MARKET_NOT_LISTED);

        Exp memory newCollateralFactorExp = Exp({mantissa : newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa : collateralFactorMaxMantissa});
        require(!lessThanExp(highLimit, newCollateralFactorExp), INVALID_COLLATERAL_FACTOR);

        // If collateral factor != 0, fail if price == 0
        require(newCollateralFactorMantissa == 0 || oracle.getUnderlyingPrice(address(kToken)) != 0, "price error");

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(kToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external onlyAdmin() {
        require(newLiquidationIncentiveMantissa <= liquidationIncentiveMaxMantissa, INVALID_LIQUIDATION_INCENTIVE);
        require(newLiquidationIncentiveMantissa >= liquidationIncentiveMinMantissa, INVALID_LIQUIDATION_INCENTIVE);

        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param kToken The address of the market (token) to list
      */
    function _supportMarket(KToken kToken) external onlyAdmin() {
        require(!markets[address(kToken)].isListed, MARKET_ALREADY_LISTED);

        kToken.isKToken();
        // Sanity check to make sure its really a KToken

        markets[address(kToken)] = Market({isListed : true, collateralFactorMantissa : 0});

        _addMarketInternal(address(kToken));

        emit MarketListed(kToken);
    }

    function _addMarketInternal(address kToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != KToken(kToken), MARKET_ALREADY_ADDED);
        }
        allMarkets.push(KToken(kToken));
    }


    /**
      * @notice Set the given borrow caps for the given kToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or capGuardian can call this function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param kTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    function _setMarketBorrowCaps(KToken[] calldata kTokens, uint[] calldata newBorrowCaps) external {
        require(msg.sender == admin || msg.sender == capGuardian, "only admin or cap guardian can set borrow caps");

        uint numMarkets = kTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for (uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(kTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(kTokens[i], newBorrowCaps[i]);
        }
    }

    /**
      * @notice Set the given supply caps for the given kToken markets. Supplying that brings total supply to or above supply cap will revert.
      * @dev Admin or capGuardian can call this function to set the supply caps. A supply cap of 0 corresponds to unlimited supplying.
      * @param kTokens The addresses of the markets (tokens) to change the supply caps for
      * @param newSupplyCaps The new supply cap values in underlying to be set. A value of 0 corresponds to unlimited supplying.
      */
    function _setMarketSupplyCaps(KToken[] calldata kTokens, uint[] calldata newSupplyCaps) external {
        require(msg.sender == admin || msg.sender == capGuardian, "only admin or cap guardian can set supply caps");

        uint numMarkets = kTokens.length;
        uint numSupplyCaps = newSupplyCaps.length;

        require(numMarkets != 0 && numMarkets == numSupplyCaps, "invalid input");

        for (uint i = 0; i < numMarkets; i++) {
            supplyCaps[address(kTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(kTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow and Supply Cap Guardian
     * @param newCapGuardian The address of the new Cap Guardian
     */
    function _setCapGuardian(address newCapGuardian) external onlyAdmin() {
        address oldCapGuardian = capGuardian;
        capGuardian = newCapGuardian;
        emit NewCapGuardian(oldCapGuardian, newCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     */
    function _setPauseGuardian(address newPauseGuardian) external onlyAdmin() {
        address oldPauseGuardian = pauseGuardian;
        pauseGuardian = newPauseGuardian;
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);
    }

    function _setMintPaused(KToken kToken, bool state) public returns (bool) {
        require(markets[address(kToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause/unpause");

        mintGuardianPaused[address(kToken)] = state;
        emit ActionPaused(kToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(KToken kToken, bool state) public returns (bool) {
        require(markets[address(kToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause/unpause");

        borrowGuardianPaused[address(kToken)] = state;
        emit ActionPaused(kToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause/unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause/unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        unitroller._acceptImplementation();
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (KToken[] memory) {
        return allMarkets;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    function getOracle() external view returns (address) {
        return address(oracle);
    }

}
