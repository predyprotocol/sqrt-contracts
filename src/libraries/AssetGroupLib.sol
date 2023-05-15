// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetGroupLib {
    function isAllow(DataType.PairGroup memory _assetGroup, uint256 _pairId) internal pure returns (bool) {
        return _pairId < _assetGroup.assetsCount;
    }
}
