// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/Controller.sol";

contract Helper {
    uint256 internal constant RISK_RATIO = 109544511;

    function createAssetStatus(uint256 _pairId, address _weth, address _uniswapPool)
        internal
        view
        returns (DataType.PairStatus memory assetStatus)
    {
        assetStatus = DataType.PairStatus(
            _pairId,
            DataType.AssetPoolStatus(
                address(0),
                address(0),
                ScaledAsset.createTokenStatus(),
                InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
                0
            ),
            DataType.AssetPoolStatus(
                _weth,
                address(0),
                ScaledAsset.createTokenStatus(),
                InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
                0
            ),
            DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
            Perp.createAssetStatus(_uniswapPool, -100, 100),
            false,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp
        );

        assetStatus.sqrtAssetStatus.supplyPremiumGrowth = 1 * 1e16;
        assetStatus.sqrtAssetStatus.borrowPremiumGrowth = 2 * 1e16;
        assetStatus.sqrtAssetStatus.fee0Growth = 200 * 1e12;
        assetStatus.sqrtAssetStatus.fee1Growth = 5 * 1e12;
    }
}
