// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle is ICompoundOracle {
    address public constant wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant cEth = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    mapping(address => uint256) public prices;

    function getUnderlyingPrice(address _cToken) public view returns (uint256) {
        if (_cToken == cEth) return prices[wEth];
        return prices[ICToken(_cToken).underlying()];
    }

    function setUnderlyingPrice(address _cToken, uint256 _underlyingPriceMantissa) public {
        if (_cToken == cEth) prices[wEth] = _underlyingPriceMantissa;
        else prices[ICToken(_cToken).underlying()] = _underlyingPriceMantissa;
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
