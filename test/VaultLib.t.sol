// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/VaultLib.sol";
import "./helper/Helper.sol";

contract VaultLibTest is Test, Helper {
    DataType.OwnVaults ownVaults1;
    DataType.OwnVaults ownVaults2;

    DataType.PairGroup internal pairGroup;

    DataType.Vault internal vault;

    mapping(uint256 => DataType.PairStatus) internal pairs;

    address internal user = vm.addr(uint256(1));

    function setUp() public virtual {
        VaultLib.addIsolatedVaultId(ownVaults2, 200);

        // create pair group
        pairGroup = DataType.PairGroup(address(0), 4, 4);

        // create pair status
        pairs[1] = createAssetStatus(1, address(0), address(0), false);
        pairs[2] = createAssetStatus(2, address(0), address(0), true);
        pairs[3] = createAssetStatus(3, address(0), address(0), false);

        vault.id = 1;
        vault.owner = user;
    }

    // add pair and get the pair
    function testCreateOrGetUserStatus() public {
        VaultLib.createOrGetUserStatus(pairs, vault, 1);
        VaultLib.createOrGetUserStatus(pairs, vault, 1);

        assertEq(vault.openPositions.length, 1);
        assertEq(vault.openPositions[0].pairId, 1);
    }

    // add isolated pair and get the pair
    function testCreateUserStatusWithIsolated() public {
        VaultLib.createOrGetUserStatus(pairs, vault, 2);
        VaultLib.createOrGetUserStatus(pairs, vault, 2);

        assertEq(vault.openPositions.length, 1);
        assertEq(vault.openPositions[0].pairId, 2);
    }

    // add second pair
    function testCreateUserStatusSecondly() public {
        VaultLib.createOrGetUserStatus(pairs, vault, 1);
        VaultLib.createOrGetUserStatus(pairs, vault, 3);

        assertEq(vault.openPositions.length, 2);
        assertEq(vault.openPositions[0].pairId, 1);
        assertEq(vault.openPositions[1].pairId, 3);
    }

    // can not add isolated pair
    function testCannotAddIsolatedPair() public {
        VaultLib.createOrGetUserStatus(pairs, vault, 1);

        vm.expectRevert(bytes("ISOLATED"));
        VaultLib.createOrGetUserStatus(pairs, vault, 2);

        assertEq(vault.openPositions.length, 1);
        assertEq(vault.openPositions[0].pairId, 1);
    }

    // can not add second pair to isolated vault
    function testCannotAddPairToIsolatedVault() public {
        VaultLib.createOrGetUserStatus(pairs, vault, 2);

        vm.expectRevert(bytes("ISOLATED"));
        VaultLib.createOrGetUserStatus(pairs, vault, 3);

        assertEq(vault.openPositions.length, 1);
        assertEq(vault.openPositions[0].pairId, 2);
    }

    function testUpdateMainVaultId() public {
        VaultLib.updateMainVaultId(ownVaults1, 50);

        assertEq(ownVaults1.mainVaultId, 50);
    }

    function testCannotUpdateMainVaultId() public {
        VaultLib.updateMainVaultId(ownVaults1, 50);

        vm.expectRevert(bytes("V4"));
        VaultLib.updateMainVaultId(ownVaults1, 51);
    }

    function testAddIsolatedVaultId() public {
        VaultLib.addIsolatedVaultId(ownVaults1, 100);

        assertEq(ownVaults1.isolatedVaultIds.length, 1);
        assertEq(ownVaults1.isolatedVaultIds[0], 100);
    }

    function testCannotAddIsolatedVaultId_IfVaultIdIsZero() public {
        vm.expectRevert(bytes("V1"));
        VaultLib.addIsolatedVaultId(ownVaults1, 0);
    }

    function testCannotAddIsolatedVaultId_IfNumOfVaultsExceedsMax() public {
        for (uint256 i; i < 100; i++) {
            VaultLib.addIsolatedVaultId(ownVaults1, i + 1);
        }

        vm.expectRevert(bytes("V3"));
        VaultLib.addIsolatedVaultId(ownVaults1, 200);
    }

    function testRemoveIsolatedVaultId() public {
        VaultLib.removeIsolatedVaultId(ownVaults2, 200);

        assertEq(ownVaults2.isolatedVaultIds.length, 0);
    }

    function testCannotRemoveIsolatedVaultId_IfNotFound() public {
        vm.expectRevert(bytes("V3"));
        VaultLib.removeIsolatedVaultId(ownVaults2, 123);
    }

    function testCannotRemoveIsolatedVaultId_IfVaultIdIsZero() public {
        vm.expectRevert(bytes("V1"));
        VaultLib.removeIsolatedVaultId(ownVaults2, 0);
    }
}
