// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./PairGroupLib.sol";
import "./DataType.sol";
import "./ScaledAsset.sol";

library VaultLib {
    using PairGroupLib for DataType.PairGroup;

    uint256 internal constant MAX_VAULTS = 100;

    function getUserStatus(
        DataType.PairGroup memory _pairGroup,
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        DataType.Vault storage _vault,
        uint64 _pairId
    ) internal returns (Perp.UserStatus storage userStatus) {
        checkVault(_vault, msg.sender);

        require(_pairGroup.isAllow(_pairId), "ASSETID");

        userStatus = createOrGetUserStatus(_pairs, _vault, _pairId);
    }

    function checkVault(DataType.Vault memory _vault, address _caller) internal pure {
        require(_vault.id > 0, "V1");
        require(_vault.owner == _caller, "V2");
    }

    function createOrGetUserStatus(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        DataType.Vault storage _vault,
        uint64 _pairId
    ) internal returns (Perp.UserStatus storage) {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            if (_vault.openPositions[i].pairId == _pairId) {
                return _vault.openPositions[i];
            }
        }

        if (_vault.openPositions.length >= 1) {
            // vault must not be isolated and _pairId must not be isolated
            require(
                !_pairs[_vault.openPositions[0].pairId].isIsolatedMode && !_pairs[_pairId].isIsolatedMode, "ISOLATED"
            );
        }

        _vault.openPositions.push(Perp.createPerpUserStatus(_pairId));

        return _vault.openPositions[_vault.openPositions.length - 1];
    }

    function cleanOpenPosition(DataType.Vault storage _vault, uint256 _pairId) internal {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            Perp.UserStatus memory userStatus = _vault.openPositions[i];

            if (userStatus.pairId == _pairId && userStatus.perp.amount == 0 && userStatus.sqrtPerp.amount == 0) {
                removeOpenPosition(_vault, i);

                return;
            }
        }
    }

    function removeOpenPosition(DataType.Vault storage _vault, uint256 _index) internal {
        _vault.openPositions[_index] = _vault.openPositions[_vault.openPositions.length - 1];
        _vault.openPositions.pop();
    }

    function updateMainVaultId(DataType.OwnVaults storage _ownVaults, uint256 _mainVaultId) internal {
        require(_ownVaults.mainVaultId == 0, "V4");

        _ownVaults.mainVaultId = _mainVaultId;
    }

    function addIsolatedVaultId(DataType.OwnVaults storage _ownVaults, uint256 _newIsolatedVaultId) internal {
        require(_newIsolatedVaultId > 0, "V1");

        _ownVaults.isolatedVaultIds.push(_newIsolatedVaultId);

        require(_ownVaults.isolatedVaultIds.length <= MAX_VAULTS, "V3");
    }

    function removeIsolatedVaultId(DataType.OwnVaults storage _ownVaults, uint256 _vaultId) internal {
        require(_vaultId > 0, "V1");

        if (_ownVaults.mainVaultId == _vaultId) {
            return;
        }

        uint256 index = getIsolatedVaultIndex(_ownVaults, _vaultId);

        removeIsolatedVaultIdWithIndex(_ownVaults, index);
    }

    function removeIsolatedVaultIdWithIndex(DataType.OwnVaults storage _ownVaults, uint256 _index) internal {
        _ownVaults.isolatedVaultIds[_index] = _ownVaults.isolatedVaultIds[_ownVaults.isolatedVaultIds.length - 1];
        _ownVaults.isolatedVaultIds.pop();
    }

    function getIsolatedVaultIndex(DataType.OwnVaults memory _ownVaults, uint256 _vaultId)
        internal
        pure
        returns (uint256)
    {
        uint256 index = type(uint256).max;

        for (uint256 i = 0; i < _ownVaults.isolatedVaultIds.length; i++) {
            if (_ownVaults.isolatedVaultIds[i] == _vaultId) {
                index = i;
                break;
            }
        }

        require(index <= MAX_VAULTS, "V3");

        return index;
    }
}
