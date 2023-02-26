// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./GammaShortStrategy.sol";
import "./StrategyQuoter.sol";

contract StrategyFactory {
    event StrategyCreated(address strategyAddress, address quoterAddress, uint256 assetId, address creator);

    function createStrategy(
        address _controller,
        address _reader,
        uint256 _assetId,
        BaseStrategy.MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) external returns (address strategyAddress, address quoterAddress) {
        GammaShortStrategy strategy = new GammaShortStrategy(
            _controller,
            _reader,
            _assetId,
            _minPerValueLimit,
            _name,
            _symbol
        );

        quoterAddress = address(new StrategyQuoter(strategy));

        strategy.transferOwnership(msg.sender);

        strategyAddress = address(strategy);

        emit StrategyCreated(strategyAddress, quoterAddress, _assetId, msg.sender);
    }
}
