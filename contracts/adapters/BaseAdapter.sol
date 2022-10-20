// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BaseAdapter is ERC4626 {
    using SafeTransferLib for ERC20;
    using SafeERC20 for IERC20;

    address public immutable vault;

    constructor(ERC20 _asset, address _vault) ERC4626(_asset, "Base Adapter", "RSN8_BA") {
        vault = _vault;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(vault).balanceOf(address(this)); //consider overriding
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    function afterDeposit(uint256 assets, uint256 shares) internal override {}

}