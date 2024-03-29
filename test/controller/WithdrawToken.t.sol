// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestControllerWithdrawToken is TestController {
    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    uint256 vaultId;

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user1, type(uint128).max);
        weth.mint(user1, type(uint128).max);
        usdc.mint(user2, type(uint128).max);
        weth.mint(user2, type(uint128).max);

        vm.startPrank(user1);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        vm.stopPrank();

        vm.prank(user2);
        vaultId = controller.updateMargin(PAIR_GROUP_ID, 1e10);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return getTradeParamsWithTokenId(WETH_ASSET_ID, _tradeAmount, _tradeSqrtAmount);
    }

    function testCannotWithdrawToken_IfAmountIsZero() public {
        controller.supplyToken(WETH_ASSET_ID, 100, false);

        vm.expectRevert(bytes("AZ"));
        controller.withdrawToken(WETH_ASSET_ID, 0, false);
    }

    function testCannotWithdrawToken_IfAssetIdIsZero() public {
        controller.supplyToken(WETH_ASSET_ID, 100, false);

        vm.expectRevert(bytes("PAIR0"));
        controller.withdrawToken(0, 100, false);
    }

    function testCannotWithdrawToken_IfAssetIdIsNotExisted() public {
        controller.supplyToken(WETH_ASSET_ID, 100, false);

        vm.expectRevert(bytes("PAIR0"));
        controller.withdrawToken(4, 100, false);
    }

    // withdraw token
    function testWithdrawToken() public {
        controller.supplyToken(WETH_ASSET_ID, 100, false);

        controller.withdrawToken(WETH_ASSET_ID, 100, false);

        assertEq(IERC20(getSupplyTokenAddress(WETH_ASSET_ID)).balanceOf(address(this)), 0);
    }

    // cannot withdraw token if asset utilization is not 0
    function testCannotWithdrawTokenIfNoEnoughUnderlyingAsset() public {
        vm.prank(user1);
        controller.supplyToken(WETH_ASSET_ID, 1e6, false);

        vm.startPrank(user2);
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(-100, 0));
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(bytes("S0"));
        controller.withdrawToken(WETH_ASSET_ID, 1e6, false);
    }

    // cannot withdraw token if asset utilization is not 0
    function testCannotWithdrawTokenIfNoEnoughStableAsset() public {
        vm.prank(user1);
        controller.supplyToken(WETH_ASSET_ID, 1e6, true);

        vm.startPrank(user2);
        controller.tradePerp(vaultId, WETH_ASSET_ID, getTradeParams(100, 0));
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(bytes("S0"));
        controller.withdrawToken(WETH_ASSET_ID, 1e6, true);
    }
}
