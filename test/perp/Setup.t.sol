// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../../src/libraries/Perp.sol";
import "../mocks/MockERC20.sol";
import "../../src/libraries/InterestRateModel.sol";

contract TestPerp is Test {
    uint256 internal constant RISK_RATIO = 109544511;

    MockERC20 internal usdc;
    MockERC20 internal weth;
    address internal token0;
    address internal token1;
    IUniswapV3Pool internal uniswapPool;

    DataType.AssetStatus internal underlyingAssetStatus;
    ScaledAsset.TokenStatus internal stableAssetStatus;
    Perp.UserStatus internal userStatus;

    function setUp() public virtual {
        usdc = new MockERC20("usdc", "USDC", 6);
        weth = new MockERC20("weth", "WETH", 18);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));

        if (isTokenAToken0) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
        }

        usdc.mint(address(this), 1e18);
        weth.mint(address(this), 1e18);

        address factory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(address(usdc), address(weth), 500));

        uniswapPool.initialize(2 ** 96);

        uniswapPool.mint(address(this), -1000, 1000, 1000000, bytes(""));

        underlyingAssetStatus = DataType.AssetStatus(
            1,
            address(weth),
            address(0),
            DataType.AssetRiskParams(RISK_RATIO, 1000, 500),
            ScaledAsset.createTokenStatus(),
            Perp.createAssetStatus(address(uniswapPool), -100, 100),
            !isTokenAToken0,
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
            block.timestamp,
            0
        );
        stableAssetStatus = ScaledAsset.createTokenStatus();
        userStatus = Perp.createPerpUserStatus();

        ScaledAsset.addAsset(underlyingAssetStatus.tokenStatus, 1000);
        ScaledAsset.addAsset(stableAssetStatus, 10000);
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (amount0 > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, amount1);
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(token0, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(token1, msg.sender, uint256(amount1Delta));
        }
    }
}
