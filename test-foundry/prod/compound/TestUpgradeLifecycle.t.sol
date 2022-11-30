// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./TestLifecycle.t.sol";

contract TestUpgradeLifecycle is TestLifecycle {
    function setUp() public override {
        super.setUp();

        _upgrade();
    }
}
