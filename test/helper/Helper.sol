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
        return createAssetStatus(_pairId, _weth, _uniswapPool, false);
    }

    function createAssetStatus(uint256 _pairId, address _weth, address _uniswapPool, bool _isIsolatedMode)
        internal
        view
        returns (DataType.PairStatus memory assetStatus)
    {
        assetStatus = DataType.PairStatus(
            _pairId,
            1,
            DataType.AssetPoolStatus(
                address(0),
                address(0),
                ScaledAsset.createTokenStatus(),
                InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18)
            ),
            DataType.AssetPoolStatus(
                _weth, address(0), ScaledAsset.createTokenStatus(), InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18)
            ),
            DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
            Perp.createAssetStatus(_uniswapPool, -100, 100),
            false,
            _isIsolatedMode,
            block.timestamp
        );
    }
}
