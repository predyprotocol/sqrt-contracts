// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../../src/strategy/GammaShortStrategy.sol";
import "../../src/strategy/StrategyQuoter.sol";
import "./Setup.t.sol";
import "forge-std/console.sol";

contract TestGammaShortStrategy is TestBaseStrategy {
    Reader reader;
    GammaShortStrategy internal strategy;
    StrategyQuoter internal quoter;

    uint256 lpVaultId;

    address internal user = vm.addr(uint256(1));
    address internal user2 = vm.addr(uint256(2));

    function setUp() public override {
        TestBaseStrategy.setUp();

        reader = new Reader(controller);

        controller.supplyToken(1, 1e15);
        controller.supplyToken(2, 1e15);

        strategy = new GammaShortStrategy();

        strategy.initialize(
            address(controller),
            address(reader),
            WETH_ASSET_ID,
            BaseStrategy.MinPerValueLimit(10 * 1e16, 40 * 1e16),
            "GS",
            "GS"
        );
        quoter = new StrategyQuoter(strategy);

        usdc.mint(user, type(uint128).max);

        usdc.approve(address(strategy), type(uint256).max);
        vm.prank(user);
        usdc.approve(address(strategy), type(uint256).max);

        strategy.depositForPositionInitialization(1e10, -6 * 1e10, 6 * 1e10, getStrategyTradeParams());

        lpVaultId = controller.updateMargin(1e10);

        // Min / VaultValue must be greater than 1%
        assertGt(getMinPerVaultValue(), 1e16);
    }

    function getStrategyTradeParams() internal view returns (IStrategyVault.StrategyTradeParams memory) {
        return IStrategyVault.StrategyTradeParams(0, type(uint256).max, block.timestamp);
    }

    function getMinPerVaultValue() internal returns (uint256) {
        vm.startPrank(address(strategy));
        DataType.VaultStatusResult memory vaultStatus = controller.getVaultStatus(strategy.vaultId());
        vm.stopPrank();

        return SafeCast.toUint256(vaultStatus.minDeposit * 1e18 / vaultStatus.vaultValue);
    }

    function testCannotInitialize() public {
        GammaShortStrategy.StrategyTradeParams memory tradeParams = getStrategyTradeParams();

        vm.expectRevert(bytes("GSS0"));
        strategy.depositForPositionInitialization(1e10, -1e9, 1e9, tradeParams);
    }

    function testCannotInitialize_IfCallerIsNotOwner() public {
        GammaShortStrategy.StrategyTradeParams memory tradeParams = getStrategyTradeParams();

        vm.prank(user);
        vm.expectRevert(bytes("BaseStrategy: caller is not operator"));
        strategy.depositForPositionInitialization(1e10, -1e9, 1e9, tradeParams);
    }

    function testCannotDeposit_IfDepositAmountIsTooLarge() public {
        GammaShortStrategy.StrategyTradeParams memory tradeParams = getStrategyTradeParams();

        vm.expectRevert(bytes("GSS2"));
        strategy.deposit(1e10, address(this), 1e10 - 1, false, tradeParams);
    }

    function testCannotWithdraw_IfWithdrawAmountIsTooSmall() public {
        strategy.deposit(1e10, address(this), 1e20, false, getStrategyTradeParams());

        GammaShortStrategy.StrategyTradeParams memory tradeParams = getStrategyTradeParams();

        vm.expectRevert(bytes("GSS3"));
        strategy.withdraw(1e10, address(this), 1e10, tradeParams);
    }

    function testDepositLargeAmount() public {
        uint256 depositMarginAmount =
            strategy.deposit(2 * 1e10, address(this), 5 * 1e10, false, getStrategyTradeParams());

        assertEq(depositMarginAmount, 20000000000);
    }

    function testDeposit1() public {
        vm.startPrank(user);
        uint256 balance1 = usdc.balanceOf(user);
        uint256 depositMarginAmount = strategy.deposit(1e10, user, 1e20, false, getStrategyTradeParams());
        uint256 balance2 = usdc.balanceOf(user);

        uint256 withdrawMarginAmount = strategy.withdraw(1e10, user, 0, getStrategyTradeParams());
        uint256 balance3 = usdc.balanceOf(user);
        vm.stopPrank();

        assertEq(balance1 - balance2, 10000000000);
        assertEq(balance3 - balance2, 9999990000);
        assertEq(depositMarginAmount, 10000000000);
        assertEq(withdrawMarginAmount, 9999990000);
    }

    function testDeposit1Fuzz(uint256 _amount) public {
        uint256 amount = bound(_amount, 1e6, 1e12);

        vm.startPrank(user);

        strategy.deposit(amount, user, 1e12, false, getStrategyTradeParams());

        strategy.withdraw(amount, user, 0, getStrategyTradeParams());

        vm.stopPrank();
    }

    function testDeposit2() public {
        uint256 depositMarginAmount = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        for (uint256 i; i < 100; i++) {
            uniswapPool.swap(address(this), false, -100 * 1e15, TickMath.MAX_SQRT_RATIO - 1, "");
            uniswapPool.swap(address(this), true, 100 * 1e15, TickMath.MIN_SQRT_RATIO + 1, "");
        }

        controller.tradePerp(
            lpVaultId, 2, TradeLogic.TradeParams(1e8, -1e8, 0, type(uint160).max, block.timestamp, false, "")
        );

        vm.warp(block.timestamp + 10 weeks);

        controller.tradePerp(
            lpVaultId, 2, TradeLogic.TradeParams(-1e8, 1e8, 0, type(uint160).max, block.timestamp, false, "")
        );

        uint256 withdrawAmount = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        assertEq(depositMarginAmount, 10000000000);
        assertEq(withdrawAmount, 10049200000);
    }

    function testDeposit3() public {
        uint256 depositMarginAmount = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        uniswapPool.swap(address(this), false, -5 * 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        vm.warp(block.timestamp + 1 days);

        uint256 withdrawAmount = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        assertEq(depositMarginAmount, 10000000000);
        assertEq(withdrawAmount, 9833550000);
    }

    function testDeposit4() public {
        uint256 finalDeposit1 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        uniswapPool.swap(address(this), false, -50 * 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        uint256 estimatedDepositAmount = quoter.quoteDeposit(1e10, address(this), 1e10, getStrategyTradeParams());

        uint256 finalDeposit2 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        vm.warp(block.timestamp + 1 minutes);

        uint256 withdrawAmount2 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());
        uint256 withdrawAmount1 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        assertEq(finalDeposit1, 10000000000);
        assertEq(finalDeposit2, 1377600000);
        assertEq(estimatedDepositAmount, 1377600000);

        assertEq(withdrawAmount1, 1257550000);
        assertEq(withdrawAmount2, 1257540000);
    }

    function testFrontrunnedDeposit() public {
        uint256 finalDeposit1 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        // This is the frontrunning tx
        uniswapPool.swap(address(this), false, -10 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        // Frontrunned deposit tx
        uint256 finalDeposit2 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        vm.warp(block.timestamp + 1 minutes);

        uniswapPool.swap(address(this), true, 10 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        uint256 withdrawAmount2 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());
        uint256 withdrawAmount1 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        // user1's deposit price and withdrawal price is almost same
        // user2's deposit price is low
        assertEq(finalDeposit1, 10000000000);
        assertEq(finalDeposit2, 9994190000);

        assertEq(withdrawAmount1, 10000490000);
        assertEq(withdrawAmount2, 10000490000);
    }

    function testFrontrunnedWithdraw() public {
        uint256 finalDeposit1 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        uint256 finalDeposit2 = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        // This is the frontrunning tx
        uniswapPool.swap(address(this), false, -10 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        // Frontrunned withdraw tx
        uint256 withdrawAmount2 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        vm.warp(block.timestamp + 1 minutes);

        uniswapPool.swap(address(this), true, 10 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        uint256 withdrawAmount1 = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        // user1's deposit price and withdrawal price is almost same
        // user2's withdrawal price is low
        assertEq(finalDeposit1, 10000000000);
        assertEq(finalDeposit2, 10000000000);

        assertEq(withdrawAmount1, 10000740000);
        assertEq(withdrawAmount2, 9993550000);
    }

    function testDepositAfterRebalance() public {
        uniswapPool.swap(address(this), false, -10 * 1e17, TickMath.MAX_SQRT_RATIO - 1, "");

        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, 2107);

        uint256 depositMarginAmount = strategy.deposit(1e10, address(this), 1e20, false, getStrategyTradeParams());

        vm.warp(block.timestamp + 1 days);

        uint256 withdrawMarginAmount = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        assertEq(depositMarginAmount, 9465460000);
        assertEq(withdrawMarginAmount, 9457740000);
    }

    function testCannotDeltaHedge_IfTimeHasNotPassed() public {
        strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        uniswapPool.swap(address(this), false, -1 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        assertFalse(strategy.checkPriceHedge());
        assertFalse(strategy.checkTimeHedge());

        vm.expectRevert(bytes("TG"));
        strategy.execDeltaHedge(getStrategyTradeParams());
    }

    function testDeltaHedgeByTime() public {
        vm.warp(block.timestamp + 2 days + 1 minutes);

        uniswapPool.swap(address(this), false, -20 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        uint256 depositMarginAmount = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        assertFalse(strategy.checkPriceHedge());
        assertTrue(strategy.checkTimeHedge());

        assertEq(reader.getDelta(2, strategy.vaultId()), -2399999973);
        strategy.execDeltaHedge(getStrategyTradeParams());
        assertEq(reader.getDelta(2, strategy.vaultId()), -30);

        uint256 withdrawMarginAmount = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        uniswapPool.swap(address(this), true, 15 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        vm.warp(block.timestamp + 1 hours);

        assertEq(depositMarginAmount, 9975920000);
        assertEq(withdrawMarginAmount, 9974650000);
    }

    function testDeltaHedgeByPriceUp() public {
        strategy.updateHedgePriceThreshold(10120000000 * 1e8);

        uniswapPool.swap(address(this), false, -20 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        assertTrue(strategy.checkPriceHedge());
        assertFalse(strategy.checkTimeHedge());

        strategy.execDeltaHedge(getStrategyTradeParams());
    }

    function testDeltaHedgeByPriceDown() public {
        strategy.updateHedgePriceThreshold(10120000000 * 1e8);

        uniswapPool.swap(address(this), true, 20 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        assertTrue(strategy.checkPriceHedge());
        assertFalse(strategy.checkTimeHedge());

        strategy.execDeltaHedge(getStrategyTradeParams());
    }

    function testDeltaHedgingFuzz(uint256 _amount) public {
        vm.warp(block.timestamp + 2 days + 1 minutes);

        uint256 amount = bound(_amount, 2 * 1e4, 1e12);

        uint256 depositMarginAmount = strategy.deposit(amount, address(this), 1e12, false, getStrategyTradeParams());

        uniswapPool.swap(address(this), false, -20 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        strategy.execDeltaHedge(getStrategyTradeParams());

        uniswapPool.swap(address(this), true, 15 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        vm.warp(block.timestamp + 1 days);

        uint256 withdrawMarginAmount = strategy.withdraw(amount, address(this), 0, getStrategyTradeParams());

        assertGt(depositMarginAmount, withdrawMarginAmount);
    }

    function testCannotUpdateGamma() public {
        strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        GammaShortStrategy.StrategyTradeParams memory tradeParams = getStrategyTradeParams();

        vm.expectRevert(bytes("GSS4"));
        strategy.updateGamma(10 * 1e10, tradeParams);
    }

    function testUpdateGamma() public {
        uint256 depositMarginAmount = strategy.deposit(1e10, address(this), 1e10, false, getStrategyTradeParams());

        uniswapPool.swap(address(this), false, -2 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");

        strategy.updateGamma(1e10, getStrategyTradeParams());

        uniswapPool.swap(address(this), true, 2 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");

        vm.warp(block.timestamp + 1 days);

        uint256 withdrawMarginAmount = strategy.withdraw(1e10, address(this), 0, getStrategyTradeParams());

        assertEq(depositMarginAmount, 10000000000);
        assertEq(withdrawMarginAmount, 9974850000);
    }

    function testSetOperator() public {
        strategy.setOperator(user2);

        assertEq(strategy.operator(), user2);
    }

    function testCannotSetOperator_IfCallerIsNotOperator() public {
        vm.prank(user2);
        vm.expectRevert(bytes("BaseStrategy: caller is not operator"));
        strategy.setOperator(user2);
    }

    function testCannotSetOperator_IfAddressIsZero() public {
        vm.expectRevert();
        strategy.setOperator(address(0));
    }
}
