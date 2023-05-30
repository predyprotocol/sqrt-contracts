// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@solmate/utils/FixedPointMathLib.sol";
import "../DataType.sol";
import "../Perp.sol";
import "../PositionCalculator.sol";
import "../ScaledAsset.sol";
import "./TradeLogic.sol";

/*
 * Error Codes
 * L1: vault must be danger before liquidation
 * L2: vault must be (safe if there are positions) or (margin is negative if there are no positions) after liquidation
 * L3: too much slippage
 * L4: close ratio must be between 0 and 1e18
 */
library LiquidationLogic {
    using ScaledAsset for ScaledAsset.TokenStatus;

    event PositionLiquidated(
        uint256 vaultId, uint256 pairId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );
    event VaultLiquidated(
        uint256 vaultId,
        uint256 mainVaultId,
        uint256 withdrawnMarginAmount,
        address liquidator,
        int256 totalPenaltyAmount
    );

    function execLiquidationCall(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        DataType.Vault storage _mainVault,
        uint256 _closeRatio,
        uint256 _liquidationSlippageSqrtTolerance
    ) external returns (int256 totalPenaltyAmount, bool isClosedAll) {
        require(0 < _closeRatio && _closeRatio <= Constants.ONE, "L4");

        // The vault must be danger
        PositionCalculator.isDanger(_pairs, _rebalanceFeeGrowthCache, _vault);

        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            Perp.UserStatus storage userStatus = _vault.openPositions[i];

            (int256 totalPayoff, uint256 penaltyAmount) = closePerp(
                _vault.id,
                _pairGroup,
                _pairs[userStatus.pairId],
                _rebalanceFeeGrowthCache,
                userStatus,
                _closeRatio,
                _liquidationSlippageSqrtTolerance
            );

            _vault.margin += totalPayoff;
            totalPenaltyAmount += int256(penaltyAmount);
        }

        (_vault.margin, totalPenaltyAmount) =
            calculatePayableReward(_vault.margin, uint256(totalPenaltyAmount) * _closeRatio / Constants.ONE);

        // The vault must be safe after liquidation call
        int256 minDeposit = PositionCalculator.isSafe(_pairs, _rebalanceFeeGrowthCache, _vault, true);

        isClosedAll = (minDeposit == 0);

        int256 withdrawnMarginAmount;

        // If the vault is isolated and margin is not negative, the contract moves vault's margin to the main vault.
        if (isClosedAll && _mainVault.id > 0 && _vault.id != _mainVault.id && _vault.margin > 0) {
            withdrawnMarginAmount = _vault.margin;

            _mainVault.margin += _vault.margin;

            _vault.margin = 0;
        }

        // withdrawnMarginAmount is always positive because it's checked in before lines
        emit VaultLiquidated(_vault.id, _mainVault.id, uint256(withdrawnMarginAmount), msg.sender, totalPenaltyAmount);
    }

    function calculatePayableReward(int256 reserveBefore, uint256 expectedReward)
        internal
        pure
        returns (int256 reserveAfter, int256 payableReward)
    {
        if (reserveBefore >= int256(expectedReward)) {
            return (reserveBefore - int256(expectedReward), int256(expectedReward));
        } else if (reserveBefore >= 0) {
            return (0, reserveBefore);
        } else {
            return (0, reserveBefore);
        }
    }

    function closePerp(
        uint256 _vaultId,
        DataType.PairGroup memory _pairGroup,
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus storage _perpUserStatus,
        uint256 _closeRatio,
        uint256 _sqrtSlippageTolerance
    ) internal returns (int256 totalPayoff, uint256 penaltyAmount) {
        int256 tradeAmount = -_perpUserStatus.perp.amount * int256(_closeRatio) / int256(Constants.ONE);
        int256 tradeAmountSqrt = -_perpUserStatus.sqrtPerp.amount * int256(_closeRatio) / int256(Constants.ONE);

        uint160 sqrtTwap = UniHelper.getSqrtTWAP(_pairStatus.sqrtAssetStatus.uniswapPool);

        DataType.TradeResult memory tradeResult = TradeLogic.trade(
            _pairGroup, _pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus, tradeAmount, tradeAmountSqrt
        );

        totalPayoff = tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        {
            // reverts if price is out of slippage threshold
            uint256 sqrtPrice = UniHelper.getSqrtPrice(_pairStatus.sqrtAssetStatus.uniswapPool);

            uint256 liquidationSlippageSqrtTolerance = calculateLiquidationSlippageTolerance(_sqrtSlippageTolerance);
            penaltyAmount = calculatePenaltyAmount(_pairGroup.marginRoundedDecimal);

            require(
                sqrtTwap * 1e6 / (1e6 + liquidationSlippageSqrtTolerance) <= sqrtPrice
                    && sqrtPrice <= sqrtTwap * (1e6 + liquidationSlippageSqrtTolerance) / 1e6,
                "L3"
            );
        }

        emit PositionLiquidated(
            _vaultId, _pairStatus.id, tradeAmount, tradeAmountSqrt, tradeResult.payoff, tradeResult.fee
        );
    }

    function calculateLiquidationSlippageTolerance(uint256 _sqrtSlippageTolerance) internal pure returns (uint256) {
        if (_sqrtSlippageTolerance == 0) {
            return Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE;
        } else if (_sqrtSlippageTolerance <= Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE) {
            return _sqrtSlippageTolerance;
        } else {
            return Constants.MAX_LIQ_SLIPPAGE_SQRT_TOLERANCE;
        }
    }

    function calculatePenaltyAmount(uint8 _marginRoundedDecimal) internal pure returns (uint256) {
        return 100 * (10 ** _marginRoundedDecimal);
    }
}
