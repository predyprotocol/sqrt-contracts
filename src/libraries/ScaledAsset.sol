// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@solmate/utils/FixedPointMathLib.sol";
import "./Constants.sol";
import "./math/Math.sol";

library ScaledAsset {
    using Math for int256;

    struct TokenStatus {
        uint256 totalCompoundDeposited;
        uint256 totalNormalDeposited;
        uint256 totalNormalBorrowed;
        uint256 assetScaler;
        uint256 assetGrowth;
        uint256 debtGrowth;
    }

    struct UserStatus {
        int256 positionAmount;
        uint256 lastFeeGrowth;
    }

    event ScaledAssetPositionUpdated(uint256 pairId, bool isStable, int256 open, int256 close);

    function createTokenStatus() internal pure returns (TokenStatus memory) {
        return TokenStatus(0, 0, 0, Constants.ONE, 0, 0);
    }

    function createUserStatus() internal pure returns (UserStatus memory) {
        return UserStatus(0, 0);
    }

    function addAsset(TokenStatus storage tokenState, uint256 _amount) internal returns (uint256 claimAmount) {
        if (_amount == 0) {
            return 0;
        }

        claimAmount = FixedPointMathLib.mulDivDown(_amount, Constants.ONE, tokenState.assetScaler);

        tokenState.totalCompoundDeposited += claimAmount;
    }

    function removeAsset(TokenStatus storage tokenState, uint256 _supplyTokenAmount, uint256 _amount)
        internal
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        if (_amount == 0) {
            return (0, 0);
        }

        require(_supplyTokenAmount > 0, "S3");

        uint256 burnAmount = FixedPointMathLib.mulDivDown(_amount, Constants.ONE, tokenState.assetScaler);

        if (_supplyTokenAmount < burnAmount) {
            finalBurnAmount = _supplyTokenAmount;
        } else {
            finalBurnAmount = burnAmount;
        }

        finalWithdrawAmount = FixedPointMathLib.mulDivDown(finalBurnAmount, tokenState.assetScaler, Constants.ONE);

        require(getAvailableCollateralValue(tokenState) >= finalWithdrawAmount, "S0");

        tokenState.totalCompoundDeposited -= finalBurnAmount;
    }

    function updatePosition(
        ScaledAsset.TokenStatus storage tokenStatus,
        ScaledAsset.UserStatus storage userStatus,
        int256 _amount,
        uint256 _pairId,
        bool _isStable
    ) internal {
        // Confirms fee has been settled before position updating.
        if (userStatus.positionAmount > 0) {
            require(userStatus.lastFeeGrowth == tokenStatus.assetGrowth, "S2");
        } else if (userStatus.positionAmount < 0) {
            require(userStatus.lastFeeGrowth == tokenStatus.debtGrowth, "S2");
        }

        int256 openAmount;
        int256 closeAmount;

        if (userStatus.positionAmount * _amount >= 0) {
            openAmount = _amount;
        } else {
            if (userStatus.positionAmount.abs() >= _amount.abs()) {
                closeAmount = _amount;
            } else {
                openAmount = userStatus.positionAmount + _amount;
                closeAmount = -userStatus.positionAmount;
            }
        }

        if (closeAmount > 0) {
            tokenStatus.totalNormalBorrowed -= uint256(closeAmount);
        } else if (closeAmount < 0) {
            require(getAvailableCollateralValue(tokenStatus) >= uint256(-closeAmount), "S0");
            tokenStatus.totalNormalDeposited -= uint256(-closeAmount);
        }

        if (openAmount > 0) {
            tokenStatus.totalNormalDeposited += uint256(openAmount);

            userStatus.lastFeeGrowth = tokenStatus.assetGrowth;
        } else if (openAmount < 0) {
            require(getAvailableCollateralValue(tokenStatus) >= uint256(-openAmount), "S0");

            tokenStatus.totalNormalBorrowed += uint256(-openAmount);

            userStatus.lastFeeGrowth = tokenStatus.debtGrowth;
        }

        userStatus.positionAmount += _amount;

        emit ScaledAssetPositionUpdated(_pairId, _isStable, openAmount, closeAmount);
    }

    function computeUserFee(ScaledAsset.TokenStatus memory _assetStatus, ScaledAsset.UserStatus memory _userStatus)
        internal
        pure
        returns (int256 interestFee)
    {
        if (_userStatus.positionAmount > 0) {
            interestFee = int256(getAssetFee(_assetStatus, _userStatus));
        } else {
            interestFee = -int256(getDebtFee(_assetStatus, _userStatus));
        }
    }

    function settleUserFee(ScaledAsset.TokenStatus memory _assetStatus, ScaledAsset.UserStatus storage _userStatus)
        internal
        returns (int256 interestFee)
    {
        interestFee = computeUserFee(_assetStatus, _userStatus);

        if (_userStatus.positionAmount > 0) {
            _userStatus.lastFeeGrowth = _assetStatus.assetGrowth;
        } else {
            _userStatus.lastFeeGrowth = _assetStatus.debtGrowth;
        }
    }

    function getAssetFee(TokenStatus memory tokenState, UserStatus memory accountState)
        internal
        pure
        returns (uint256)
    {
        require(accountState.positionAmount >= 0, "S1");

        return FixedPointMathLib.mulDivDown(
            tokenState.assetGrowth - accountState.lastFeeGrowth,
            // never overflow
            uint256(accountState.positionAmount),
            Constants.ONE
        );
    }

    function getDebtFee(TokenStatus memory tokenState, UserStatus memory accountState)
        internal
        pure
        returns (uint256)
    {
        require(accountState.positionAmount <= 0, "S1");

        return FixedPointMathLib.mulDivUp(
            tokenState.debtGrowth - accountState.lastFeeGrowth,
            // never overflow
            uint256(-accountState.positionAmount),
            Constants.ONE
        );
    }

    // update scaler
    function updateScaler(TokenStatus storage tokenState, uint256 _interestRate) internal {
        if (tokenState.totalCompoundDeposited == 0 && tokenState.totalNormalDeposited == 0) {
            return;
        }

        // supply interest rate is InterestRate * Utilization
        uint256 supplyInterestRate = FixedPointMathLib.mulDivDown(
            _interestRate, getTotalDebtValue(tokenState), getTotalCollateralValue(tokenState)
        );

        // round up
        tokenState.debtGrowth += _interestRate;
        tokenState.assetScaler =
            FixedPointMathLib.mulDivDown(tokenState.assetScaler, Constants.ONE + supplyInterestRate, Constants.ONE);
        tokenState.assetGrowth += supplyInterestRate;
    }

    function getTotalCollateralValue(TokenStatus memory tokenState) internal pure returns (uint256) {
        return FixedPointMathLib.mulDivDown(tokenState.totalCompoundDeposited, tokenState.assetScaler, Constants.ONE)
            + tokenState.totalNormalDeposited;
    }

    function getTotalDebtValue(TokenStatus memory tokenState) internal pure returns (uint256) {
        return tokenState.totalNormalBorrowed;
    }

    function getAvailableCollateralValue(TokenStatus memory tokenState) internal pure returns (uint256) {
        return getTotalCollateralValue(tokenState) - getTotalDebtValue(tokenState);
    }

    function getUtilizationRatio(TokenStatus memory tokenState) internal pure returns (uint256) {
        if (tokenState.totalCompoundDeposited == 0 && tokenState.totalNormalDeposited == 0) {
            return 0;
        }

        uint256 utilization = FixedPointMathLib.mulDivDown(
            getTotalDebtValue(tokenState), Constants.ONE, getTotalCollateralValue(tokenState)
        );

        if (utilization > 1e18) {
            return 1e18;
        }

        return utilization;
    }
}
