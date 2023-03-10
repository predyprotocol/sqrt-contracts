// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract TestControllerCallback is TestController {
    uint256 vaultId;

    address internal user = vm.addr(uint256(1));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user, type(uint128).max);
        weth.mint(user, type(uint128).max);

        vm.prank(user);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user);
        weth.approve(address(controller), type(uint256).max);

        vm.prank(user);
        controller.supplyToken(1, 1e10);
        vm.prank(user);
        controller.supplyToken(2, 1e10);

        vaultId = controller.updateMargin(0, 1e8);
    }

    function predyTradeCallback(DataType.TradeResult memory, bytes calldata) external {
        TradeLogic.TradeParams memory tradeParams = TradeLogic.TradeParams(
            1 * 1e8, 0, getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp, false, ""
        );

        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testCannotTradePerp() public {
        TradeLogic.TradeParams memory tradeParams = TradeLogic.TradeParams(
            5 * 1e8, 0, getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp, true, ""
        );

        vm.expectRevert(bytes("NS"));
        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);
    }

    function testTradePerp() public {
        TradeLogic.TradeParams memory tradeParams = TradeLogic.TradeParams(
            4 * 1e8, 0, getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp, true, ""
        );

        controller.tradePerp(vaultId, WETH_ASSET_ID, tradeParams);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.openPositions[0].perpTrade.perp.amount, 500000000);
    }
}
