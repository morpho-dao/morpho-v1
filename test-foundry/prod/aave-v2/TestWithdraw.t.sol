// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using WadRayMath for uint256;

    function _beforeWithdraw() internal virtual {}

    struct WithdrawTest {
        TestMarket market;
        //
        uint256 morphoBalanceOnPoolBefore;
        uint256 morphoUnderlyingBalanceBefore;
        //
        uint256 p2pSupplyIndex;
        uint256 poolSupplyIndex;
        //
        uint256 balanceInP2P;
        uint256 balanceOnPool;
        //
        uint256 suppliedOnPoolBefore;
        uint256 suppliedInP2PBefore;
        uint256 totalSuppliedBefore;
        //
        uint256 suppliedOnPoolAfter;
        uint256 suppliedInP2PAfter;
        uint256 totalSuppliedAfter;
    }

    function _testShouldWithdrawMarketP2PAndOnPool(TestMarket memory _market, uint96 _amount)
        internal
    {
        WithdrawTest memory test;
        test.market = _market;

        test.morphoBalanceOnPoolBefore = ERC20(_market.poolToken).balanceOf(address(morpho));
        test.morphoUnderlyingBalanceBefore = ERC20(_market.underlying).balanceOf(address(morpho));

        uint256 price = oracle.getAssetPrice(_market.underlying);
        uint256 amount = bound(
            _amount,
            (MIN_ETH_AMOUNT * 10**_market.decimals) / price,
            Math.min((MAX_ETH_AMOUNT * 10**_market.decimals) / price, type(uint96).max)
        );

        _tip(_market.underlying, address(user), amount);

        user.approve(_market.underlying, amount);
        user.supply(_market.poolToken, address(user), amount);

        _forward(100_000);

        morpho.updateIndexes(_market.poolToken);

        test.p2pSupplyIndex = morpho.p2pSupplyIndex(_market.poolToken);
        (, test.poolSupplyIndex, ) = morpho.poolIndexes(_market.poolToken);

        (test.balanceInP2P, test.balanceOnPool) = morpho.supplyBalanceInOf(
            _market.poolToken,
            address(user)
        );

        test.suppliedInP2PBefore = test.balanceInP2P.rayMul(test.p2pSupplyIndex);
        test.suppliedOnPoolBefore = test.balanceOnPool.rayMul(test.poolSupplyIndex);
        test.totalSuppliedBefore = test.suppliedOnPoolBefore + test.suppliedInP2PBefore;

        _beforeWithdraw();

        user.withdraw(_market.poolToken, type(uint256).max);

        assertApproxEqAbs(
            ERC20(_market.underlying).balanceOf(address(user)),
            test.totalSuppliedBefore,
            1,
            "unexpected underlying balance after withdraw"
        );

        (test.suppliedInP2PAfter, test.suppliedOnPoolAfter, test.totalSuppliedAfter) = lens
        .getCurrentSupplyBalanceInOf(_market.poolToken, address(user));

        assertEq(test.suppliedOnPoolAfter, 0, "unexpected pool underlying balance");
        assertEq(test.suppliedInP2PAfter, 0, "unexpected p2p underlying balance");
        assertEq(test.totalSuppliedAfter, 0, "unexpected total underlying supplied");
    }

    function testShouldWithdrawAllMarketsP2PAndOnPool(uint96 _amount) public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            _revert();

            _testShouldWithdrawMarketP2PAndOnPool(activeMarkets[marketIndex], _amount);
        }
    }

    function testShouldNotWithdrawZeroAmount() public {
        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(PositionsManagerUtils.AmountIsZero.selector);
            user.withdraw(market.poolToken, 0);
        }
    }

    function testShouldNotWithdrawFromUnenteredMarket(uint96 _amount) public {
        vm.assume(_amount > 0);

        for (uint256 marketIndex; marketIndex < activeMarkets.length; ++marketIndex) {
            TestMarket memory market = activeMarkets[marketIndex];

            vm.expectRevert(ExitPositionsManager.UserNotMemberOfMarket.selector);
            user.withdraw(market.poolToken, _amount);
        }
    }
}
