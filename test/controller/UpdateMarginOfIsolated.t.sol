// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerupdateMarginOfIsolated is TestController {
    // non vault
    address internal user1 = vm.addr(uint256(1));
    // main vault
    address internal user2 = vm.addr(uint256(2));

    uint256 vaultId2;
    uint256 isolatedVaultId2;

    function setUp() public override {
        TestController.setUp();

        controller.supplyToken(WETH_ASSET_ID, 1e10, true);
        controller.supplyToken(WETH_ASSET_ID, 1e10, false);

        usdc.mint(user1, 1000 * 1e6);
        usdc.mint(user2, 2100 * 1e6);

        vm.prank(user1);
        usdc.approve(address(controller), type(uint256).max);

        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);

        vaultId2 = controller.updateMargin(PAIR_GROUP_ID, 1100 * 1e6);

        isolatedVaultId2 = controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, 100 * 1e6, true);

        vm.stopPrank();
    }

    ////////////////
    //  Deposit   //
    ////////////////

    // Cannot withdraw margin if caller is not owner
    function testCannotupdateMarginOfIsolated_IfCallerHasNoVault() public {
        vm.expectRevert(bytes("NS"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, -100, true);

        vm.expectRevert(bytes("NS"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, -100, false);
    }

    // Cannot deposit margin if pair group is not existing
    function testCannotupdateMarginOfIsolated_IfPairGroupIdDoesNotExist() public {
        vm.startPrank(user2);

        vm.expectRevert(bytes("INVALID_PG"));
        controller.updateMarginOfIsolated(0, 0, 100, true);

        vm.expectRevert(bytes("INVALID_PG"));
        controller.updateMarginOfIsolated(INVALID_PAIR_GROUP_ID, 0, 100, true);

        vm.stopPrank();
    }

    // Cannot deposit margin with 0
    function testCannotupdateMarginOfIsolated_IfAmountIsZero() public {
        vm.startPrank(user2);

        vm.expectRevert(bytes("AZ"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, 0, false);

        vm.stopPrank();
    }

    function testCannotDepositMargin_IfAccountDoesNotHaveMainVault() public {
        vm.startPrank(user1);

        vm.expectRevert(bytes("V1"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, 1000 * 1e6, true);

        vm.stopPrank();
    }

    function testDepositMargin_IfAccountDoesNotHaveMainVault() public {
        vm.startPrank(user1);

        uint256 isolatedVaultId = controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, 100 * 1e6, false);

        vm.stopPrank();

        DataType.Vault memory isolatedVault = controller.getVault(isolatedVaultId);
        assertEq(isolatedVault.margin, 100 * 1e6);
    }

    // deposit margin
    function testDepositMargin() public {
        uint256 beforeUsdcBalance = usdc.balanceOf(user2);
        vm.prank(user2);
        uint256 vaultId = controller.updateMarginOfIsolated(PAIR_GROUP_ID, 0, 100 * 1e6, true);
        uint256 afterUsdcBalance = usdc.balanceOf(user2);

        assertEq(vaultId, 3);
        assertEq(controller.vaultCount(), 4);
        assertEq(beforeUsdcBalance - afterUsdcBalance, 0);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId);
        assertEq(vault.margin, 100 * 1e6);

        DataType.Vault memory vault2 = controller.getVault(vaultId2);
        assertEq(vault2.margin, 900 * 1e6);
    }

    function testDepositMargin_AnotherPairGroup() public {
        vm.prank(user2);
        uint256 vaultId = controller.updateMarginOfIsolated(PAIR_GROUP_ID + 1, 0, 100 * 1e6, false);

        assertEq(vaultId, 3);
        assertEq(controller.vaultCount(), 4);
    }

    // deposit margin if vault is insolvent

    ////////////////
    //  Withdraw  //
    ////////////////

    // Cannot withdraw margin if margin becomes negative
    function testCannotWithdrawMargin_IfMarginBecomesNegative() public {
        vm.startPrank(user2);

        vm.expectRevert(bytes("NS"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, isolatedVaultId2, -1000 * 1e6 - 1, true);

        vm.stopPrank();
    }

    // cannot withdraw margin if vault is not safe
    function testCannotWithdrawMargin_IfVaultHasPosition() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParamsWithTokenId(WETH_ASSET_ID, 1000, 0);

        vm.startPrank(user2);

        controller.tradePerp(isolatedVaultId2, WETH_ASSET_ID, tradeParams);

        vm.expectRevert(bytes("NS"));
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, isolatedVaultId2, -100 * 1e6, true);

        vm.stopPrank();
    }

    // withdraw margin
    function testWithdrawMargin() public {
        vm.prank(user2);
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, isolatedVaultId2, -100 * 1e6, true);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 1100 * 1e6);
    }

    // withdraw margin
    function testWithdrawAllMargin() public {
        vm.prank(user2);
        controller.updateMarginOfIsolated(PAIR_GROUP_ID, isolatedVaultId2, 0, true);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 1100 * 1e6);
    }
}
