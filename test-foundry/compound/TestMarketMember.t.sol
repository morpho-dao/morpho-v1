// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestMarketMember is TestSetup {
    using CompoundMath for uint256;

    function testShouldNotWithdrawWhenNotMarketMember() public {
        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier1.withdraw(cDai, 1 ether);
    }

    function testShouldNotRepayWhenNotMarketMember() public {
        supplier1.approve(dai, 1 ether);
        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier1.repay(cDai, 1 ether);
    }

    function testShouldNotLiquidateUserNotOnMemberOfMarketAsCollateral() public {
        supplier1.approve(wEth, 1 ether);
        supplier1.supply(cEth, 1 ether);
        supplier1.borrow(cUsdc, to6Decimals(1 ether));

        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier2.liquidate(cUsdc, cDai, address(supplier1), 1 ether);
    }

    function testShouldNotLiquidateUserNotOnMemberOfMarketAsBorrow() public {
        supplier1.approve(wEth, 1 ether);
        supplier1.supply(cEth, 1 ether);
        supplier1.borrow(cUsdc, to6Decimals(1 ether));

        hevm.expectRevert(abi.encodeWithSignature("UserNotMemberOfMarket()"));
        supplier2.liquidate(cDai, cEth, address(supplier1), 1 ether);
    }
}
