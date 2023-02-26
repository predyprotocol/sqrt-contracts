// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "../libraries/DataType.sol";

interface IPredyTradeCallback {
    function predyTradeCallback(DataType.TradeResult memory _tradeResult, bytes calldata data) external;
}
