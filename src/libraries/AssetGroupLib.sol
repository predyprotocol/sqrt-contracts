// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetGroupLib {
    function isAllow(DataType.AssetGroup memory _assetGroup, uint256 _assetId) internal pure returns (bool) {
        return _assetId < _assetGroup.assetsCount;
    }
}
