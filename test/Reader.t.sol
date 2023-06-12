// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./controller/Setup.t.sol";
import "../src/Reader.sol";

contract TestReader is TestController {
    Reader reader;

    uint256 vaultId1;
    uint256 vaultId2;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user1, type(uint128).max);
        weth.mint(user1, type(uint128).max);
        usdc.mint(user2, type(uint128).max);

        vm.startPrank(user1);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        controller.supplyToken(1, 1e10, true);
        controller.supplyToken(1, 1e10, false);
        vaultId1 = controller.updateMargin(1e10);
        vm.stopPrank();

        // create vault
        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        vaultId2 = controller.updateMargin(1e10);
        vm.stopPrank();

        reader = new Reader(controller);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    function testGetMinDeposit() public {
        vm.startPrank(user1);
        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(-1000 * 1e6, 1000 * 1e6));
        vm.stopPrank();

        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(800 * 1e6, -800 * 1e6));
        vm.stopPrank();

        manipulateVol(10);
        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(user2);
        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(vaultId2);
        vm.stopPrank();

        assertEq(vaultStatus.vaultValue, 9999303495);
        assertEq(vaultStatus.minDeposit, 7998021);
    }

    function testGetDelta1() public {
        vm.startPrank(user1);
        controller.tradePerp(vaultId1, WETH_ASSET_ID, getTradeParams(-1000 * 1e6, 1000 * 1e6));
        vm.stopPrank();

        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(1000, -2000));
        vm.stopPrank();

        assertEq(reader.getDelta(WETH_ASSET_ID, vaultId2), -1000);
    }

    function testGetDelta2() public {
        vm.startPrank(user2);
        controller.tradePerp(vaultId2, WETH_ASSET_ID, getTradeParams(-1000, 2000));
        vm.stopPrank();

        assertEq(reader.getDelta(WETH_ASSET_ID, vaultId2), 999);
    }
}
