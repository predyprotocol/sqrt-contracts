// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./Setup.t.sol";

contract TestControllerIsolatedVault is TestController {
    uint256 vaultId1;
    uint256 vaultId2;

    address internal user1 = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    uint256 isolatedPairId;

    function setUp() public override {
        TestController.setUp();

        usdc.mint(user1, type(uint128).max);
        weth.mint(user1, type(uint128).max);
        wbtc.mint(user1, type(uint128).max);
        usdc.mint(user2, type(uint128).max);

        vm.startPrank(user1);
        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        wbtc.approve(address(controller), type(uint256).max);
        controller.supplyToken(1, 1e10, true);
        controller.supplyToken(1, 1e10, false);
        controller.supplyToken(2, 1e10, true);
        controller.supplyToken(2, 1e10, false);
        vaultId1 = controller.updateMargin(PAIR_GROUP_ID, 1e10);
        vm.stopPrank();

        // create vault
        vm.startPrank(user2);
        usdc.approve(address(controller), type(uint256).max);
        vaultId2 = controller.updateMargin(PAIR_GROUP_ID, 1e10);
        vm.stopPrank();

        addIsolatedPair();
    }

    function addIsolatedPair() internal {
        isolatedPairId = controller.addPair(
            DataType.AddPairParams(
                PAIR_GROUP_ID,
                address(uniswapPool),
                true,
                DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );

        controller.supplyToken(isolatedPairId, 1e10, true);
        controller.supplyToken(isolatedPairId, 1e10, false);
    }

    function getTradeParams(int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return TradePerpLogic.TradeParams(
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
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(-45 * 1e8, 0);

        vm.expectRevert(bytes("V2"));
        controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, tradeParams);
    }

    function testCannotOpenIsolatedVault_IfMarginBecomesNegative() public {
        vm.startPrank(user2);
        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(-45 * 1e8, 0);
        vm.expectRevert(bytes("NS"));
        controller.openIsolatedVault(1e10 + 1, WETH_ASSET_ID, tradeParams);
        vm.stopPrank();
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

    function testCannotAddPosition_IfExistingPositionIsIsolatedPair() public {
        vm.startPrank(user2);
        (uint256 isolatedVaultId,) =
            controller.openIsolatedVault(10 * 1e8, uint64(isolatedPairId), getTradeParams(-10 * 1e6, 10 * 1e6));

        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(-10 * 1e6, 10 * 1e6);

        vm.expectRevert(bytes("ISOLATED"));
        controller.tradePerp(isolatedVaultId, WETH_ASSET_ID, tradeParams);
        vm.stopPrank();
    }

    function testCannotAddPosition_WithIsolatedPairPosition() public {
        vm.startPrank(user2);
        (uint256 isolatedVaultId,) =
            controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-10 * 1e6, 10 * 1e6));

        TradePerpLogic.TradeParams memory tradeParams = getTradeParams(-10 * 1e6, 10 * 1e6);

        vm.expectRevert(bytes("ISOLATED"));
        controller.tradePerp(isolatedVaultId, uint64(isolatedPairId), tradeParams);
        vm.stopPrank();
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

    function testCannotCloseIsolatedVault_IfVaultHasPositions() public {
        vm.startPrank(user1);
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-20 * 1e8, 0));

        controller.tradePerp(isolatedVaultId, WBTC_ASSET_ID, getTradeParams(-10 * 1e6, 10 * 1e6));

        IsolatedVaultLogic.CloseParams memory closeParams = getCloseParams();

        vm.expectRevert(bytes("I2"));
        controller.closeIsolatedVault(isolatedVaultId, WETH_ASSET_ID, closeParams);

        vm.stopPrank();
    }

    function testCloseIsolatedVault() public {
        vm.startPrank(user2);
        (uint256 isolatedVaultId,) = controller.openIsolatedVault(10 * 1e8, WETH_ASSET_ID, getTradeParams(-45 * 1e8, 0));

        DataType.TradeResult memory tradeResult =
            controller.closeIsolatedVault(isolatedVaultId, WETH_ASSET_ID, getCloseParams());
        vm.stopPrank();

        assertEq(tradeResult.payoff.perpPayoff, -4501127);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
        assertEq(tradeResult.minDeposit, 0);

        DataType.Vault memory vault = controller.getVault(isolatedVaultId);
        assertEq(vault.margin, 0);
    }
}
