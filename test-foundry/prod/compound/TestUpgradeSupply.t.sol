// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestSupply.t.sol";

contract TestUpgradeSupply is TestSupply {
    function _onSetUp() internal override {
        super._onSetUp();

        _upgrade();
    }
}
