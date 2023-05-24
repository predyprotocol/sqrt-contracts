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
        wbtc.mint(user2, type(uint128).max);

        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        wbtc.approve(address(controller), type(uint256).max);

        controller.supplyToken(WETH_ASSET_ID, 1e10, true);
        controller.supplyToken(WETH_ASSET_ID, 1e10, false);
        controller.supplyToken(WBTC_ASSET_ID, 1e10, true);
        controller.supplyToken(WBTC_ASSET_ID, 1e10, false);
        vm.stopPrank();

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

        assertEq(vault.margin, 58198887);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 400000);
    }

    function testLiquidationCall_IsolatedVault() public {
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(1e8, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        vm.prank(liquidator);
        controller.liquidationCall(isolatedVaultId, DEFAULT_CLOSE_RATIO);

        DataType.Vault memory vault = controller.getVault(isolatedVaultId);

        assertEq(vault.margin, 0);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 400000);
    }

    // liquidation call with interest paid
    function testLiquidationCallWithFee() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(-1000 * 1e6, 1000 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(800 * 1e6, -800 * 1e6));

        controller.updateMargin(-92000000);

        manipulateVol(40);
        vm.warp(block.timestamp + 1 minutes);

        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);

        assertEq(controller.getVault(vaultId).margin, 6460000);
    }

    // vault becomes insolvent
    function testInsolvent() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-8 * 1e7, 0));

        uniswapPool.swap(address(this), false, 7 * 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        uint256 beforeBalance = usdc.balanceOf(address(this));
        controller.liquidationCall(vaultId, DEFAULT_CLOSE_RATIO);
        uint256 afterBalance = usdc.balanceOf(address(this));
        assertEq(beforeBalance - afterBalance, 23532567);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 0);

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

    function testLiquidationCallPartially() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        vm.prank(liquidator);
        controller.liquidationCall(vaultId, 5 * 1e17);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 79098687);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 200000);
    }

    function testLiquidationCallPartially_IsolatedVault() public {
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(1e8, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 0));

        uniswapPool.swap(address(this), false, 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 hours);

        vm.prank(liquidator);
        controller.liquidationCall(isolatedVaultId, 5 * 1e17);

        DataType.Vault memory vault = controller.getVault(isolatedVaultId);

        assertEq(vault.margin, 79098687);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 200000);
    }

    // liquidates a vault that has multiple asset positions.
    function testLiquidationCallWithMultipleAssets() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e8, 2 * 1e8));
        controller.tradePerp(vaultId, WBTC_ASSET_ID, getTradeParams(-4 * 1e8, 2 * 1e8));

        uniswapPool.swap(address(this), false, 5 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
        wbtcUniswapPool.swap(address(this), false, 5 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        checkTick(493);

        vm.warp(block.timestamp + 1 weeks);

        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId);
        assertEq(vaultStatus.vaultValue, 68418614);
        assertEq(vaultStatus.minDeposit, 93054575);

        vm.prank(liquidator);
        controller.liquidationCall(vaultId, 1e18);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 67372980);

        // check liquidation reward
        assertEq(usdc.balanceOf(liquidator), 800000);
    }
}
