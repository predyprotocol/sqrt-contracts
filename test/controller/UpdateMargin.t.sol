// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerUpdateMargin is TestController {
    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));
    uint256 vaultId2;

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user1, 1000 * 1e6);
        usdc.mint(user2, 2000 * 1e6);

        vm.prank(user1);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        vaultId2 = controller.updateMargin(1000 * 1e6);

        controller.supplyToken(1, 1e10);
        controller.supplyToken(2, 1e10);
    }

    function testDepositMargin_IfAccountAlreadyHasMainVault() public {
        vm.prank(user2);
        controller.updateMargin(1000 * 1e6);

        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 2000 * 1e6);
    }

    // Cannot withdraw margin if caller is not owner
    function testCannotUpdateMargin_IfCallerHasNoVault() public {
        vm.expectRevert(bytes("M1"));
        controller.updateMargin(-100);
    }

    // deposit margin
    function testDepositMargin() public {
        uint256 beforeUsdcBalance = usdc.balanceOf(user1);
        vm.prank(user1);
        uint256 vaultId = controller.updateMargin(1000 * 1e6);
        uint256 afterUsdcBalance = usdc.balanceOf(user1);

        assertEq(vaultId, 2);
        assertEq(controller.vaultCount(), 3);
        assertEq(beforeUsdcBalance - afterUsdcBalance, 1000 * 1e6);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId);
        assertEq(vault.margin, 1000 * 1e6);
    }

    // deposit margin if vault is insolvent

    // withdraw margin
    function testWithdrawMargin() public {
        uint256 beforeUsdcBalance = usdc.balanceOf(user2);
        vm.prank(user2);
        controller.updateMargin(-1000 * 1e6);
        uint256 afterUsdcBalance = usdc.balanceOf(user2);

        assertEq(afterUsdcBalance - beforeUsdcBalance, 1000 * 1e6);

        // check vault
        DataType.Vault memory vault = controller.getVault(vaultId2);
        assertEq(vault.margin, 0);
    }

    // Cannot withdraw margin if margin becomes negative
    function testCannotWithdrawMargin_IfMarginBecomesNegative() public {
        vm.prank(user2);
        vm.expectRevert(bytes("M1"));
        controller.updateMargin(-1000 * 1e6 - 1);
    }

    // cannot withdraw margin if vault is not safe
    function testCannotWithdrawMargin_IfVaultHasPosition() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParamsWithTokenId(WETH_ASSET_ID, 1000, 0);

        vm.prank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, tradeParams);

        vm.prank(user2);
        vm.expectRevert(bytes("NS"));
        controller.updateMargin(-1000 * 1e6);
    }
}
