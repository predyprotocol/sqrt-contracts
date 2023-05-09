// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./ScaledAsset.sol";
import "./DataType.sol";

library AssetLib {
    function checkUnderlyingAsset(DataType.AssetStatus memory underlyingAsset) internal pure {
        require(underlyingAsset.id > 0, "ASSETID");
    }
}
