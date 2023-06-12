// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../../interfaces/IPredyTradeCallback.sol";
import "../DataType.sol";
import "../Perp.sol";
import "../PositionCalculator.sol";
import "../Trade.sol";
import "../VaultLib.sol";
import "../AssetLib.sol";
import "./UpdateMarginLogic.sol";
import "./TradeLogic.sol";

/*
 * Error Codes
 * T1: tx too old
 * T2: too much slippage
 * T3: margin must be positive
 */
library TradePerpLogic {
    using VaultLib for DataType.Vault;

    struct TradeParams {
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
        bool enableCallback;
        bytes data;
    }

    event PositionUpdated(
        uint256 vaultId, uint256 pairId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );

    function execTrade(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault storage _vault,
        uint256 _pairId,
        Perp.UserStatus storage _openPosition,
        TradeParams memory _tradeParams
    ) public returns (DataType.TradeResult memory tradeResult) {
        DataType.PairStatus storage pairStatus = _pairs[_pairId];

        AssetLib.checkUnderlyingAsset(pairStatus);

        checkDeadline(_tradeParams.deadline);

        tradeResult = TradeLogic.trade(
            _pairGroup,
            pairStatus,
            _rebalanceFeeGrowthCache,
            _openPosition,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt
        );

        // remove the open position from the vault
        _vault.cleanOpenPosition();

        _vault.margin += tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        checkPrice(pairStatus.sqrtAssetStatus.uniswapPool, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice);

        if (_tradeParams.enableCallback) {
            // Calls callback function
            int256 marginAmount = IPredyTradeCallback(msg.sender).predyTradeCallback(tradeResult, _tradeParams.data);

            require(marginAmount > 0, "T3");

            _vault.margin += marginAmount;

            UpdateMarginLogic.execMarginTransfer(_vault, pairStatus.stablePool.token, marginAmount);

            UpdateMarginLogic.emitEvent(_vault, marginAmount);
        }

        tradeResult.minDeposit = PositionCalculator.checkSafe(_pairs, _rebalanceFeeGrowthCache, _vault);

        emit PositionUpdated(
            _vault.id,
            pairStatus.id,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt,
            tradeResult.payoff,
            tradeResult.fee
        );
    }

    function checkDeadline(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "T1");
    }

    function checkPrice(address _uniswapPool, uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = UniHelper.getSqrtPrice(_uniswapPool);

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "T2");
    }
}
