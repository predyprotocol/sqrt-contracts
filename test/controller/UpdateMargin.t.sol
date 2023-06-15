// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerUpdateMargin is TestController {
    // non vault
    address internal user1 = vm.addr(uint256(1));
    // main vault
    address internal user2 = vm.addr(uint256(2));

    uint256 vaultId2;
    uint256 isolatedVaultId;

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

        (isolatedVaultId,) = controller.openIsolatedVault(
            100 * 1e6, WETH_ASSET_ID, getTradeParamsWithTokenId(WETH_ASSET_ID, -10 * 1e6, 10 * 1e6)
        );

        vm.stopPrank();
    }

    ////////////////
    //  Deposit   //
    ////////////////

    // Cannot withdraw margin if caller is not owner
    function testCannotUpdateMargin_IfCallerHasNoVault() public {
        vm.expectRevert(bytes("NS"));
        controller.updateMargin(PAIR_GROUP_ID, -100);
    }

    // Cannot deposit margin if pair group is not existing
    function testCannotUpdateMargin_IfPairGroupIdDoesNotExist() public {
        vm.expectRevert(bytes("INVALID_PG"));
        controller.updateMargin(0, 100);

        vm.expectRevert(bytes("INVALID_PG"));
        controller.updateMargin(INVALID_PAIR_GROUP_ID, 100);
    }

    // Cannot deposit margin with 0
    function testCannotUpdateMargin_IfAmountIsZero() public {
        vm.expectRevert(bytes("UML0"));
        controller.updateMargin(PAIR_GROUP_ID, 0);
    }

    function testDepositMargin_IfAccountAlreadyHasMainVault() public {
        vm.prank(user2);
        controller.updateMargin(PAIR_GROUP_ID, 1000 * 1e6);

        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 2000 * 1e6);
    }

    // deposit margin
    function testDepositMargin() public {
        uint256 beforeUsdcBalance = usdc.balanceOf(user1);
        vm.prank(user1);
        uint256 vaultId = controller.updateMargin(PAIR_GROUP_ID, 1000 * 1e6);
        uint256 afterUsdcBalance = usdc.balanceOf(user1);

        assertEq(vaultId, 3);
        assertEq(controller.vaultCount(), 4);
        assertEq(beforeUsdcBalance - afterUsdcBalance, 1000 * 1e6);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId);
        assertEq(vault.margin, 1000 * 1e6);
    }

    // deposit margin if vault is insolvent

    ////////////////
    //  Withdraw  //
    ////////////////

    // Cannot withdraw margin if margin becomes negative
    function testCannotWithdrawMargin_IfMarginBecomesNegative() public {
        vm.prank(user2);
        vm.expectRevert(bytes("NS"));
        controller.updateMargin(PAIR_GROUP_ID, -1000 * 1e6 - 1);
    }

    // cannot withdraw margin if vault is not safe
    function testCannotWithdrawMargin_IfVaultHasPosition() public {
        TradePerpLogic.TradeParams memory tradeParams = getTradeParamsWithTokenId(WETH_ASSET_ID, 1000, 0);

        vm.prank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, tradeParams);

        vm.prank(user2);
        vm.expectRevert(bytes("NS"));
        controller.updateMargin(PAIR_GROUP_ID, -1000 * 1e6);
    }
    
    // withdraw margin
    function testWithdrawMargin() public {
        uint256 beforeUsdcBalance = usdc.balanceOf(user2);
        vm.prank(user2);
        controller.updateMargin(PAIR_GROUP_ID, -1000 * 1e6);
        uint256 afterUsdcBalance = usdc.balanceOf(user2);

        assertEq(afterUsdcBalance - beforeUsdcBalance, 1000 * 1e6);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 0);
    }
}
