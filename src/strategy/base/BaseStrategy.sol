// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IController.sol";
import "../../libraries/Constants.sol";

contract BaseStrategy is ERC20Upgradeable {
    struct MinPerValueLimit {
        uint256 lower;
        uint256 upper;
    }

    IController internal controller;

    uint256 public vaultId;

    address internal usdc;

    uint256 internal assetId;

    MinPerValueLimit internal minPerValueLimit;

    address public operator;

    event OperatorUpdated(address operator);

    modifier onlyOperator() {
        require(operator == msg.sender, "BaseStrategy: caller is not operator");
        _;
    }

    constructor() {}

    function initialize(
        address _controller,
        uint256 _pairId,
        MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        ERC20Upgradeable.__ERC20_init(_name, _symbol);

        controller = IController(_controller);

        assetId = _pairId;

        minPerValueLimit = _minPerValueLimit;

        DataType.PairStatus memory asset = controller.getAsset(assetId);

        usdc = asset.stablePool.token;

        operator = msg.sender;
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;

        emit OperatorUpdated(_newOperator);
    }
}
