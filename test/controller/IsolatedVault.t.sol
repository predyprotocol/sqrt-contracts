// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./Setup.t.sol";

contract TestControllerIsolatedVault is TestController {
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
        controller.supplyToken(1, 1e10);
        controller.supplyToken(2, 1e10);
        vaultId1 = controller.updateMargin(1e10);
        vm.stopPrank();

        // create vault
        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        vaultId2 = controller.updateMargin(1e10);
        vm.stopPrank();
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradeLogic.TradeParams memory)
    {
        return TradeLogic.TradeParams(
            _tradeAmount,
            _tradeSqrtAmount,
            getLowerSqrtPrice(WETH_ASSET_ID),
            getUpperSqrtPrice(WETH_ASSET_ID),
            block.timestamp,
            false,
            ""
        );
    }

    function getCloseParams() internal view returns (IsolatedVaultLogic.CloseParams memory) {
        return IsolatedVaultLogic.CloseParams(
            getLowerSqrtPrice(WETH_ASSET_ID), getUpperSqrtPrice(WETH_ASSET_ID), block.timestamp
        );
    }

    function testCannotOpenIsolatedVault_IfCallerIsNotOwner() public {
        TradeLogic.TradeParams memory tradeParams = getTradeParams(-45 * 1e8, 0);

        vm.expectRevert(bytes("V1"));
        controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, tradeParams);
    }

    function testOpenIsolatedVault() public {
        vm.startPrank(user2);
        (, DataType.TradeResult memory tradeResult) =
            controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-45 * 1e8, 0));
        vm.stopPrank();

        assertEq(tradeResult.payoff.perpEntryUpdate, 4497749979);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
        assertGt(tradeResult.minDeposit, 0);
        assertEq(controller.vaultCount(), 4);
    }

    function testCannotCloseIsolatedVault_IfCallerIsNotOwner() public {
        vm.startPrank(user1);
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-20 * 1e8, 0));
        vm.stopPrank();

        IsolatedVaultLogic.CloseParams memory closeParams = getCloseParams();

        vm.startPrank(user2);

        vm.expectRevert(bytes("V2"));
        controller.closeIsolatedVault(isolatedVaultId, WETH_ASSET_ID, closeParams);

        vm.expectRevert(bytes("V1"));
        controller.closeIsolatedVault(0, WETH_ASSET_ID, closeParams);

        vm.expectRevert(bytes("V1"));
        controller.closeIsolatedVault(1000, WETH_ASSET_ID, closeParams);

        vm.stopPrank();
    }

    function testCloseIsolatedVault() public {
        vm.startPrank(user2);
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-45 * 1e8, 0));

        DataType.TradeResult memory tradeResult =
            controller.closeIsolatedVault(isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        vm.stopPrank();

        assertEq(tradeResult.payoff.perpPayoff, -4510000);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
        assertEq(tradeResult.minDeposit, 0);
    }
}
