// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestDeltas is TestSetup {
    using CompoundMath for uint256;

    struct DeltasTest {
        TestMarket market;
        //
        uint256 p2pSupplyIndex;
        uint256 p2pBorrowIndex;
        uint256 poolSupplyIndex;
        uint256 poolBorrowIndex;
        //
        uint256 p2pSupplyDelta;
        uint256 p2pBorrowDelta;
        //
        uint256 p2pSupplyBefore;
        uint256 p2pBorrowBefore;
        uint256 p2pSupplyAfter;
        uint256 p2pBorrowAfter;
        //
        uint256 avgSupplyRatePerBlock;
        uint256 avgBorrowRatePerBlock;
    }

    function testShouldClearP2P() public virtual {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            // _revert(); // TODO: re-add as soon as https://github.com/foundry-rs/foundry/issues/3792 is resolved, to avoid sharing state changes with each market test

            DeltasTest memory test;
            test.market = markets[marketIndex];

            if (test.market.mintGuardianPaused || test.market.borrowGuardianPaused) continue;

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyBefore,
                test.p2pBorrowBefore
            ) = morpho.deltas(test.market.poolToken);

            (
                test.p2pSupplyIndex,
                test.p2pBorrowIndex,
                test.poolSupplyIndex,
                test.poolBorrowIndex
            ) = lens.getIndexes(test.market.poolToken, true);

            if (
                test.p2pSupplyBefore.mul(test.p2pSupplyIndex) <=
                test.p2pSupplyDelta.mul(test.poolSupplyIndex) ||
                test.p2pBorrowBefore.mul(test.p2pBorrowIndex) <=
                test.p2pBorrowDelta.mul(test.poolBorrowIndex)
            ) continue;

            vm.prank(morphoDao);
            morpho.increaseP2PDeltas(test.market.poolToken, type(uint256).max);

            (
                test.p2pSupplyDelta,
                test.p2pBorrowDelta,
                test.p2pSupplyAfter,
                test.p2pBorrowAfter
            ) = morpho.deltas(test.market.poolToken);

            assertApproxEqAbs(
                test.p2pSupplyDelta.mul(test.poolSupplyIndex),
                test.p2pSupplyBefore.mul(test.p2pSupplyIndex),
                10**(test.market.decimals / 2 + 1),
                "p2p supply delta"
            );
            assertApproxEqAbs(
                test.p2pBorrowDelta.mul(test.poolBorrowIndex),
                test.p2pBorrowBefore.mul(test.p2pBorrowIndex),
                10,
                "p2p borrow delta"
            );
            assertEq(test.p2pSupplyAfter, test.p2pSupplyBefore, "p2p supply");
            assertEq(test.p2pBorrowAfter, test.p2pBorrowBefore, "p2p borrow");

            (test.avgSupplyRatePerBlock, , ) = lens.getAverageSupplyRatePerBlock(
                test.market.poolToken
            );
            (test.avgBorrowRatePerBlock, , ) = lens.getAverageBorrowRatePerBlock(
                test.market.poolToken
            );

            assertApproxEqAbs(
                test.avgSupplyRatePerBlock,
                ICToken(test.market.poolToken).supplyRatePerBlock(),
                1,
                "avg supply rate per year"
            );
            assertApproxEqAbs(
                test.avgBorrowRatePerBlock,
                ICToken(test.market.poolToken).borrowRatePerBlock(),
                1,
                "avg borrow rate per year"
            );
        }
    }
}
