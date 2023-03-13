// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./Setup.t.sol";

contract TestControllerLiquidationCall is TestController {
    uint256 constant DEFAULT_CLOSE_RATIO = 1e18;

    uint256 vaultId;
    uint256 lpVaultId;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));
    address internal liquidator = vm.addr(uint256(3));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);

        vm.prank(user2);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        weth.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        controller.supplyToken(1, 1e10);
        vm.prank(user2);
        controller.supplyToken(2, 1e10);

        // create vault
        vaultId = controller.updateMargin(1e8);
        vm.prank(user2);
        lpVaultId = controller.updateMargin(1e10);

        uniswapPool.mint(address(this), -20000, 20000, 1e18, bytes(""));
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradeLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    // liquidation call
    function testLiquidationCall() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        vm.prank(liquidator);
        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 57710000);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 880000);
    }

    // liquidation call with interest paid
    function testLiquidationCallWithFee() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(-1000 * 1e6, 1000 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(800 * 1e6, -800 * 1e6));

        vm.warp(block.timestamp + 14 weeks);

        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        assertEq(controller.getVault(vaultId).margin, 11720000);
    }

    // vault becomes insolvent
    function testInsolvent() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-8 * 1e7, 0));

        uniswapPool.swap(address(this), false, 7 * 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, -23550000);

        controller.updateMargin(1e8);
    }

    // cannot exec liquidation call if vault is safe
    function testCannotLiquidate_IfVaultIsSafe() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-8 * 1e7, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.expectRevert(bytes("ND"));
        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);
    }

    // cannot exec liquidation call if the vault has no debt
    function testCannotLiquidate_IfNoDebt() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(1e8, 0));

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1e8, 0));

        vm.expectRevert(bytes("ND"));
        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);
    }

    // trade after liquidation call
    function testTradeAfterLiquidationCall() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 0));
    }

    function testCannotLiquidateAfterLiquidationCall() public {
        DataType.TradeResult memory result = controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));
        assertEq(result.minDeposit, 79999995);

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        vm.expectRevert(bytes("ND"));
        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);
    }

    // TODO:liquidation partially
}
