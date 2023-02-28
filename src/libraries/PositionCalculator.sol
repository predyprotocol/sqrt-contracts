// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@solmate/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./UniHelper.sol";
import "./DataType.sol";
import "./Constants.sol";
import "./PerpFee.sol";
import "./math/Math.sol";

library PositionCalculator {
    using ScaledAsset for ScaledAsset.TokenStatus;

    struct PositionParams {
        // x^0
        int256 amountStable;
        // x^0.5
        int256 amountSqrt;
        // x^1
        int256 amountUnderlying;
    }

    function isDanger(mapping(uint256 => DataType.AssetStatus) storage _assets, DataType.Vault memory _vault)
        internal
        view
    {
        (int256 minDeposit, int256 vaultValue, bool hasPosition) = calculateMinDeposit(_assets, _vault, true);

        if (!hasPosition) {
            revert("ND");
        }

        require(vaultValue < minDeposit || _vault.margin < 0, "ND");
    }

    function isSafe(mapping(uint256 => DataType.AssetStatus) storage _assets, DataType.Vault memory _vault)
        internal
        view
        returns (int256 minDeposit)
    {
        int256 vaultValue;
        bool hasPosition;

        // isSafe does not count unrealized fee
        (minDeposit, vaultValue, hasPosition) = calculateMinDeposit(_assets, _vault, false);

        if (!hasPosition) {
            return 0;
        }

        require(vaultValue >= minDeposit && _vault.margin >= 0, "NS");
    }

    function calculateMinDeposit(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault memory _vault,
        bool _enableUnrealizedFeeCalculation
    ) internal view returns (int256 minDeposit, int256 vaultValue, bool hasPosition) {
        int256 minValue;
        uint256 debtValue;

        (minValue, vaultValue, debtValue, hasPosition) =
            calculateMinValue(_assets, _vault, _enableUnrealizedFeeCalculation);

        int256 minMinValue = SafeCast.toInt256(calculateRequiredCollateralWithDebt(debtValue) * debtValue / 1e6);

        minDeposit = vaultValue - minValue + minMinValue;
    }

    function calculateRequiredCollateralWithDebt(uint256 _debtValue) internal pure returns (uint256) {
        return Constants.BASE_MIN_COLLATERAL_WITH_DEBT;
    }

    /**
     * @notice Calculates min value of the vault.
     * @param _assets The mapping of assets
     * @param _vault The target vault for calculation
     * @param _enableUnrealizedFeeCalculation If true calculation count unrealized fee.
     */
    function calculateMinValue(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault memory _vault,
        bool _enableUnrealizedFeeCalculation
    ) internal view returns (int256 minValue, int256 vaultValue, uint256 debtValue, bool hasPosition) {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            DataType.UserStatus memory userStatus = _vault.openPositions[i];

            uint256 assetId = userStatus.assetId;

            if (_assets[assetId].sqrtAssetStatus.uniswapPool != address(0)) {
                uint160 sqrtPrice =
                    getSqrtPrice(_assets[assetId].sqrtAssetStatus.uniswapPool, _assets[assetId].isMarginZero);

                PositionParams memory positionParams;
                if (_enableUnrealizedFeeCalculation) {
                    positionParams = getPositionWithUnrealizedFee(
                        _assets[Constants.STABLE_ASSET_ID], _assets[assetId], userStatus.perpTrade
                    );
                } else {
                    positionParams = getPosition(userStatus.perpTrade);
                }

                minValue += calculateMinValue(sqrtPrice, positionParams, _assets[assetId].riskParams.riskRatio);

                vaultValue += calculateValue(sqrtPrice, positionParams);

                debtValue += calculateSquartDebtValue(sqrtPrice, userStatus.perpTrade);

                hasPosition = hasPosition || getHasPositionFlag(userStatus.perpTrade);
            }
        }

        minValue += int256(_vault.margin);
        vaultValue += int256(_vault.margin);
    }

    function getSqrtPrice(address _uniswapPool, bool _isMarginZero) internal view returns (uint160 sqrtPriceX96) {
        return UniHelper.convertSqrtPrice(UniHelper.getSqrtTWAP(_uniswapPool), _isMarginZero);
    }

    function getPositionWithUnrealizedFee(
        DataType.AssetStatus memory _stableAsset,
        DataType.AssetStatus memory _underlyingAsset,
        Perp.UserStatus memory _perpUserStatus
    ) internal pure returns (PositionParams memory positionParams) {
        (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
            PerpFee.computeUserFee(_underlyingAsset, _stableAsset.tokenStatus, _perpUserStatus);

        return PositionParams(
            _perpUserStatus.stable.positionAmount - _perpUserStatus.sqrtPerp.stableRebalanceEntryValue
                + unrealizedFeeStable,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.underlying.positionAmount - _perpUserStatus.sqrtPerp.underlyingRebalanceEntryValue
                + unrealizedFeeUnderlying
        );
    }

    function getPosition(Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (PositionParams memory positionParams)
    {
        return PositionParams(
            _perpUserStatus.stable.positionAmount - _perpUserStatus.sqrtPerp.stableRebalanceEntryValue,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.underlying.positionAmount - _perpUserStatus.sqrtPerp.underlyingRebalanceEntryValue
        );
    }

    function getHasPositionFlag(Perp.UserStatus memory _perpUserStatus) internal pure returns (bool) {
        return _perpUserStatus.stable.positionAmount < 0 || _perpUserStatus.sqrtPerp.amount < 0
            || _perpUserStatus.underlying.positionAmount < 0;
    }

    /**
     * @notice Calculates min position value in the range `p/r` to `rp`.
     * MinValue := Min(v(rp), v(p/r), v((b/a)^2))
     * where `a` is underlying asset amount, `b` is Sqrt perp amount
     * and `c` is Stable asset amount.
     * r is risk parameter.
     */
    function calculateMinValue(uint256 _sqrtPrice, PositionParams memory _positionParams, uint256 _riskRatio)
        internal
        pure
        returns (int256 minValue)
    {
        minValue = type(int256).max;

        uint256 upperPrice = _sqrtPrice * _riskRatio / 1e8;
        uint256 lowerPrice = _sqrtPrice * 1e8 / _riskRatio;

        {
            int256 v = calculateValue(upperPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        {
            int256 v = calculateValue(lowerPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        if (_positionParams.amountSqrt < 0 && _positionParams.amountUnderlying > 0) {
            uint256 minSqrtPrice = (uint256(-_positionParams.amountSqrt) << Constants.RESOLUTION)
                / uint256(_positionParams.amountUnderlying);

            if (lowerPrice < minSqrtPrice && minSqrtPrice < upperPrice) {
                int256 v = calculateValue(minSqrtPrice, _positionParams);

                if (v < minValue) {
                    minValue = v;
                }
            }
        }
    }

    /**
     * @notice Calculates position value.
     * PositionValue = a * x+b * sqrt(x) + c.
     * where `a` is underlying asset amount, `b` is Sqrt perp amount
     * and `c` is Stable asset amount
     */
    function calculateValue(uint256 _sqrtPrice, PositionParams memory _positionParams) internal pure returns (int256) {
        int256 price = int256(_sqrtPrice * _sqrtPrice) >> Constants.RESOLUTION;

        return ((_positionParams.amountUnderlying * price) >> Constants.RESOLUTION)
            + (2 * (_positionParams.amountSqrt * int256(_sqrtPrice)) >> Constants.RESOLUTION) + _positionParams.amountStable;
    }

    function calculateSquartDebtValue(uint256 _sqrtPrice, Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (uint256)
    {
        int256 squartPosition = _perpUserStatus.sqrtPerp.amount;

        if (squartPosition > 0) {
            return 0;
        }

        return (2 * (uint256(-squartPosition) * _sqrtPrice) >> Constants.RESOLUTION);
    }
}
