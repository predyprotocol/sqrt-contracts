// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract MockAttack {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function callMintCallback(address _controller, uint256 amount0, uint256 amount1, bytes calldata data) external {
        IUniswapV3MintCallback(_controller).uniswapV3MintCallback(amount0, amount1, data);
    }

    function callSwapCallback(address _controller, int256 amount0, int256 amount1, bytes calldata data) external {
        IUniswapV3SwapCallback(_controller).uniswapV3SwapCallback(amount0, amount1, data);
    }
}
