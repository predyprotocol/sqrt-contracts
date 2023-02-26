// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";
import "forge-std/console.sol";

/*
 * https://docs.google.com/spreadsheets/d/101wXPKNGG0vqm7M6Op9WIf1GUKvvdKiCO4riO5D_iFc/edit?usp=sharing
 */
contract TestControllerTradePerp is TestController {
    uint256 vaultId;
    uint256 lpVaultId;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);
        wbtc.mint(user2, type(uint128).max);

        vm.prank(user2);
        usdc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        weth.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        wbtc.approve(address(controller), type(uint256).max);

        vm.prank(user2);
        controller.supplyToken(STABLE_ASSET_ID, 1e10);
        vm.prank(user2);
        controller.supplyToken(WETH_ASSET_ID, 1e10);
        vm.prank(user2);
        controller.supplyToken(WBTC_ASSET_ID, 1e10);

        // create vault
        vaultId = controller.updateMargin(0, 1e10);

        vm.prank(user2);
        lpVaultId = controller.updateMargin(0, 1e10);
    }

    function withdrawAll() internal {
        {
            DataType.Vault memory vault = controller.getVault(vaultId);
            for (uint256 i; i < vault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = vault.openPositions[i].perpTrade;

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    controller.tradePerp(
                        vaultId, WETH_ASSET_ID, getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount)
                    );
                }
            }

            controller.updateMargin(vaultId, -controller.getVault(vaultId).margin);
        }

        {
            vm.prank(user2);
            DataType.Vault memory lpVault = controller.getVault(lpVaultId);
            for (uint256 i; i < lpVault.openPositions.length; i++) {
                Perp.UserStatus memory perpTrade = lpVault.openPositions[i].perpTrade;

                if (perpTrade.perp.amount != 0 || perpTrade.sqrtPerp.amount != 0) {
                    TradeLogic.TradeParams memory tradeParams =
                        getTradeParams(-perpTrade.perp.amount, -perpTrade.sqrtPerp.amount);

                    vm.prank(user2);
                    controller.tradePerp(lpVaultId, WETH_ASSET_ID, tradeParams);
                }
            }

            vm.prank(user2);
            int256 margin = controller.getVault(lpVaultId).margin;
            vm.prank(user2);
            controller.updateMargin(lpVaultId, -margin);
        }

        console.log(usdc.balanceOf(address(controller)));
        console.log(weth.balanceOf(address(controller)));

        vm.prank(user2);
        controller.withdrawToken(1, 1e18);
        vm.prank(user2);
        controller.withdrawToken(2, 1e18);

        {
            DataType.AssetStatus memory asset = controller.getAsset(1);

            if (asset.accumulatedProtocolRevenue > 0) {
                controller.withdrawProtocolRevenue(1, asset.accumulatedProtocolRevenue);
            }
        }

        {
            DataType.AssetStatus memory asset = controller.getAsset(2);

            if (asset.accumulatedProtocolRevenue > 0) {
                controller.withdrawProtocolRevenue(2, asset.accumulatedProtocolRevenue);
            }
        }

        assertLt(usdc.balanceOf(address(controller)), 100);
        assertLt(weth.balanceOf(address(controller)), 100);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradeLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    function getCloseParams() internal view returns (IsolatedVaultLogic.CloseParams memory) {
        return getCloseParamsWithTokenId(WETH_ASSET_ID);
    }

    function checkTick(int24 _tick) internal {
        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, _tick);
    }

    function testCase1() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -10 * 1e6));

        uniswapPool.swap(address(this), false, 3 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 590);

        vm.prank(user2);
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -12345));

        {
            (uint256 isolatedVaultId,) =
                controller.openIsolatedVault(vaultId, 1e9, WETH_ASSET_ID, getTradeParams(-3 * 1e6, 5 * 1e6));

            uniswapPool.swap(address(this), true, -1 * 1e15, TickMath.MIN_SQRT_RATIO + 1, "");

            controller.closeIsolatedVault(vaultId, isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        }

        {
            (uint256 isolatedVaultId,) =
                controller.openIsolatedVault(vaultId, 1e9, WETH_ASSET_ID, getTradeParams(-3 * 1e6, 6 * 1e6));

            uniswapPool.swap(address(this), true, -2 * 1e15, TickMath.MIN_SQRT_RATIO + 1, "");

            controller.closeIsolatedVault(vaultId, isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        }

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1 * 1e6, 1 * 1e6 + 123));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999940000);

        withdrawAll();
    }

    function testCase2() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -10 * 1e6));

        uniswapPool.swap(address(this), false, 6 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        checkTick(1164);

        {
            (uint256 isolatedVaultId,) =
                controller.openIsolatedVault(vaultId, 1e9, WETH_ASSET_ID, getTradeParams(-3 * 1e6, 5 * 1e6));

            uniswapPool.swap(address(this), false, 2 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

            controller.closeIsolatedVault(vaultId, isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        }

        {
            (uint256 isolatedVaultId,) =
                controller.openIsolatedVault(vaultId, 1e9, WETH_ASSET_ID, getTradeParams(-3 * 1e6, 5 * 1e6));

            uniswapPool.swap(address(this), true, -3 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

            checkTick(629);

            controller.closeIsolatedVault(vaultId, isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        }

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-1 * 1e6, 10 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999290000);

        withdrawAll();
    }

    function testCase3() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));
        vm.stopPrank();

        {
            uniswapPool.swap(address(this), false, 5 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

            (, int24 currentTick,,,,,) = uniswapPool.slot0();

            assertEq(currentTick, 975);
        }

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -10 * 1e6));

        uniswapPool.swap(address(this), true, -5 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        checkTick(-1);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-4 * 1e6, 21 * 1e6));

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -11 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000750000);

        withdrawAll();
    }

    function testRebalanceOutOfRangeEdgeCase1() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 52 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1013);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10010290000);

        withdrawAll();
    }

    function testRebalanceOutOfRangeEdgeCase2() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, 100 * 1e6));

        uniswapPool.swap(address(this), false, 52 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 1013);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(0, -1 * 1e6 + 123));

        uniswapPool.swap(address(this), true, -1 * 1e15, TickMath.MIN_SQRT_RATIO + 1, "");

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000100000);

        withdrawAll();
    }

    function testMultipleAssets() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-2 * 1e6, 10 * 1e6));
        controller.tradePerp(vaultId, WBTC_ASSET_ID, getTradeParams(-10 * 1e6, 2 * 1e6));

        uniswapPool.swap(address(this), false, 1 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
        wbtcUniswapPool.swap(address(this), false, 1 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId);
        assertEq(vaultStatus.minDeposit, 3627549);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -10 * 1e6));
        controller.tradePerp(vaultId, WBTC_ASSET_ID, getTradeParams(10 * 1e6, -2 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999960000);

        withdrawAll();
    }

    function testWithdrawMarginAfterTrade() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-2 * 1e6, 10 * 1e6));
        controller.tradePerp(vaultId, WBTC_ASSET_ID, getTradeParams(-10 * 1e6, 2 * 1e6));

        uniswapPool.swap(address(this), false, 1 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
        wbtcUniswapPool.swap(address(this), false, 1 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId);
        assertEq(vaultStatus.minDeposit, 3627549);

        vm.expectRevert(bytes("NS"));
        controller.updateMargin(vaultId, -1e10 + 3 * 1e6);

        controller.updateMargin(vaultId, -1e10 + 4 * 1e6);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(2 * 1e6, -10 * 1e6));
        controller.tradePerp(vaultId, WBTC_ASSET_ID, getTradeParams(10 * 1e6, -2 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 3960000);

        withdrawAll();
    }

    function testRebalanceFee() public {
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        vm.warp(block.timestamp + 1 days);

        assertTrue(controller.reallocate(WETH_ASSET_ID));

        vm.warp(block.timestamp + 1 days);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 9999830000);

        withdrawAll();
    }

    function testShortRebalanceFee() public {
        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, 200 * 1e6));
        vm.stopPrank();

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100 * 1e6, -100 * 1e6));

        uniswapPool.swap(address(this), false, 4 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 784);

        assertTrue(controller.reallocate(WETH_ASSET_ID));

        vm.warp(block.timestamp + 1 days);

        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100 * 1e6, 100 * 1e6));

        vm.startPrank(user2);
        controller.tradePerp(lpVaultId, WETH_ASSET_ID, getTradeParams(0, -200 * 1e6));
        vm.stopPrank();

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertEq(vault.margin, 10000070000);

        withdrawAll();
    }
}
