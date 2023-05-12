// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetLib {
    function checkUnderlyingAsset(DataType.PairStatus memory underlyingAsset) internal pure {
        require(underlyingAsset.id > 0, "ASSETID");
    }

    function getRebalanceCacheId(uint256 _assetId, uint64 _rebalanceId) internal pure returns (uint256) {
        return _assetId * type(uint64).max + _rebalanceId;
    }
}
