// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/libraries/VaultLib.sol";

contract VaultLibTest is Test {
    DataType.OwnVaults ownVaults1;
    DataType.OwnVaults ownVaults2;

    function setUp() public virtual {
        VaultLib.addIsolatedVaultId(ownVaults2, 200);
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
