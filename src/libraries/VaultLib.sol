// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AssetGroupLib.sol";
import "./DataType.sol";
import "./ScaledAsset.sol";

library VaultLib {
    using AssetGroupLib for DataType.AssetGroup;

    function getUserStatus(DataType.AssetGroup storage _assetGroup, DataType.Vault storage _vault, uint256 _assetId)
        internal
        returns (DataType.UserStatus storage userStatus)
    {
        checkVault(_vault, msg.sender);

        require(_assetGroup.isAllow(_assetId), "ASSETID");

        userStatus = createOrGetUserStatus(_vault, _assetId);
    }

    function checkVault(DataType.Vault memory _vault, address _caller) internal pure {
        require(_vault.id > 0, "V1");
        require(_vault.owner == _caller, "V2");
    }

    function createOrGetUserStatus(DataType.Vault storage _vault, uint256 _assetId)
        internal
        returns (DataType.UserStatus storage)
    {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            if (_vault.openPositions[i].assetId == _assetId) {
                return _vault.openPositions[i];
            }
        }

        _vault.openPositions.push(DataType.UserStatus(_assetId, Perp.createPerpUserStatus()));

        return _vault.openPositions[_vault.openPositions.length - 1];
    }
}
