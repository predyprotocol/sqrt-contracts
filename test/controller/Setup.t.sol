// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../../src/Controller.sol";
import "../../src/libraries/InterestRateModel.sol";
import "../mocks/MockERC20.sol";

contract TestController is Test {
    struct CloseParams {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
    }

    uint256 internal constant RISK_RATIO = 109544511;

    uint64 internal constant WETH_ASSET_ID = 1;
    uint64 internal constant WBTC_ASSET_ID = 2;
    uint64 internal constant WETH2_ASSET_ID = 3;
    uint64 internal constant PAIR_GROUP_ID = 1;
    uint64 internal constant INVALID_PAIR_GROUP_ID = 3;

    Controller internal controller;
    MockERC20 internal usdc;
    MockERC20 internal weth;
    MockERC20 internal wbtc;

    address internal token0;
    address internal token1;

    IUniswapV3Pool internal uniswapPool;
    IUniswapV3Pool internal wbtcUniswapPool;
    InterestRateModel.IRMParams internal irmParams;

    function setUp() public virtual {
        irmParams = InterestRateModel.IRMParams(1e16, 9 * 1e17, 5 * 1e17, 1e18);

        // Set up tokens
        usdc = new MockERC20("usdc", "USDC", 6);
        weth = new MockERC20("weth", "WETH", 18);
        wbtc = new MockERC20("wbtc", "WBTC", 18);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));
        bool isTokenAToken0ForWBTC = uint160(address(wbtc)) < uint160(address(usdc));

        if (isTokenAToken0) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
            (weth, usdc) = (usdc, weth);
        }

        if (!isTokenAToken0ForWBTC) {
            (wbtc, usdc) = (usdc, wbtc);
        }

        usdc.mint(address(this), type(uint128).max);
        weth.mint(address(this), type(uint128).max);
        wbtc.mint(address(this), type(uint128).max);

        // Set up Uniswap pool
        address factory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(weth), address(usdc), 500));
        wbtcUniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(wbtc), address(usdc), 500));

        uniswapPool.initialize(2 ** 96);
        wbtcUniswapPool.initialize(2 ** 96);

        IUniswapV3PoolActions(address(uniswapPool)).increaseObservationCardinalityNext(180);
        IUniswapV3PoolActions(address(wbtcUniswapPool)).increaseObservationCardinalityNext(180);

        usdc.approve(address(uniswapPool), type(uint256).max);
        weth.approve(address(uniswapPool), type(uint256).max);
        usdc.approve(address(wbtcUniswapPool), type(uint256).max);
        wbtc.approve(address(wbtcUniswapPool), type(uint256).max);

        uniswapPool.mint(address(this), -2000, 2000, 1e18, bytes(""));
        wbtcUniswapPool.mint(address(this), -2000, 2000, 1e18, bytes(""));

        // Set up Controller
        controller = new Controller();
        initializeController();

        usdc.approve(address(controller), type(uint256).max);
        weth.approve(address(controller), type(uint256).max);
        wbtc.approve(address(controller), type(uint256).max);

        vm.warp(block.timestamp + 1 minutes);
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        if (amount0 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, amount1);
        }
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, uint256(amount1Delta));
        }
    }

    function initializeController() internal {
        controller.initialize();

        controller.addPairGroup(address(usdc), 4);
        controller.addPairGroup(address(usdc), 4);

        controller.addPair(
            DataType.AddPairParams(
                PAIR_GROUP_ID,
                address(uniswapPool),
                false,
                DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );

        controller.addPair(
            DataType.AddPairParams(
                PAIR_GROUP_ID,
                address(wbtcUniswapPool),
                false,
                DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );

        controller.addPair(
            DataType.AddPairParams(
                PAIR_GROUP_ID + 1,
                address(uniswapPool),
                false,
                DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );
    }

    function getTradeParamsWithTokenId(uint256 _tokenId, int256 _tradeAmount, int256 _tradeSqrtAmount)
        internal
        view
        returns (TradePerpLogic.TradeParams memory)
    {
        return TradePerpLogic.TradeParams(
            _tradeAmount,
            _tradeSqrtAmount,
            getLowerSqrtPrice(_tokenId),
            getUpperSqrtPrice(_tokenId),
            block.timestamp,
            false,
            ""
        );
    }

    function getCloseParamsWithTokenId(uint256 _tokenId) internal view returns (CloseParams memory) {
        return CloseParams(getLowerSqrtPrice(_tokenId), getUpperSqrtPrice(_tokenId), block.timestamp);
    }

    function openIsolatedVault(uint256 _depositAmount, uint64 _pairId, TradePerpLogic.TradeParams memory _tradeParams)
        internal
        returns (uint256 isolatedVaultId, DataType.TradeResult memory tradeResult)
    {
        return controller.openIsolatedPosition(0, _pairId, _tradeParams, _depositAmount);
    }

    function closeIsolatedVault(uint256 _isolatedVaultId, uint64 _pairId, CloseParams memory _closeParams)
        internal
        returns (DataType.TradeResult memory tradeResult)
    {
        Perp.UserStatus memory openPosition;

        DataType.Vault memory vault = controller.getVault(_isolatedVaultId);

        for (uint256 i; i < vault.openPositions.length; i++) {
            if (vault.openPositions[i].pairId == _pairId) {
                openPosition = vault.openPositions[i];
            }
        }

        int256 tradeAmount = -openPosition.perp.amount;
        int256 tradeAmountSqrt = -openPosition.sqrtPerp.amount;

        tradeResult = controller.closeIsolatedPosition(
            _isolatedVaultId,
            _pairId,
            TradePerpLogic.TradeParams(
                tradeAmount,
                tradeAmountSqrt,
                _closeParams.lowerSqrtPrice,
                _closeParams.upperSqrtPrice,
                _closeParams.deadline,
                false,
                ""
            ),
            0
        );
    }

    function getLowerSqrtPrice(uint256 _tokenId) internal view returns (uint160) {
        return (controller.getSqrtPrice(_tokenId) * 100) / 120;
    }

    function getUpperSqrtPrice(uint256 _tokenId) internal view returns (uint160) {
        return (controller.getSqrtPrice(_tokenId) * 120) / 100;
    }

    function getSupplyTokenAddress(uint256 _pairId) internal view returns (address supplyTokenAddress) {
        DataType.PairStatus memory asset = controller.getAsset(_pairId);

        return asset.underlyingPool.supplyTokenAddress;
    }

    function manipulateVol(uint256 _num) internal {
        for (uint256 i; i < _num; i++) {
            uniswapPool.swap(address(this), false, 5 * 1e16, TickMath.MAX_SQRT_RATIO - 1, "");
            uniswapPool.swap(address(this), true, -5 * 1e16, TickMath.MIN_SQRT_RATIO + 1, "");
        }
    }

    function checkTick(int24 _tick) internal {
        (, int24 currentTick,,,,,) = uniswapPool.slot0();

        assertEq(currentTick, _tick);
    }
}
