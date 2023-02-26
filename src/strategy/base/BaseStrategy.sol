// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IController.sol";

contract BaseStrategy is ERC20, Ownable {
    struct MinPerValueLimit {
        uint256 lower;
        uint256 upper;
    }

    IController internal immutable controller;

    uint256 public vaultId;

    address immutable usdc;

    uint256 immutable assetId;

    MinPerValueLimit minPerValueLimit;

    constructor(
        address _controller,
        uint256 _assetId,
        MinPerValueLimit memory _minPerValueLimit,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        controller = IController(_controller);

        assetId = _assetId;

        minPerValueLimit = _minPerValueLimit;

        DataType.AssetGroup memory assetGroup = controller.getAssetGroup();
        DataType.AssetStatus memory asset = controller.getAsset(assetGroup.stableAssetId);

        usdc = asset.token;

        ERC20(usdc).approve(address(controller), type(uint256).max);
    }
}
