// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import {ICToken, ICToken} from "../interfaces/compound/ICompound.sol";

/// Price Oracle for liquidation tests
contract SimplePriceOracle {
    mapping(address => uint256) public prices;

    function getUnderlyingPrice(ICToken _cToken) public view returns (uint256) {
        return prices[address(ICToken(address(_cToken)).underlying())];
    }

    function setUnderlyingPrice(ICToken _cToken, uint256 _underlyingPriceMantissa) public {
        address asset = address(ICToken(address(_cToken)).underlying());
        prices[asset] = _underlyingPriceMantissa;
    }

    function setDirectPrice(address _asset, uint256 _price) public {
        prices[_asset] = _price;
    }
}
