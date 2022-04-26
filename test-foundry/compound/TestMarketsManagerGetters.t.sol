// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestMarketsManagerGetters is TestSetup {
    function testGetAllMarkets() public {
        address[] memory allMarkets = marketsManager.getAllMarkets();

        for (uint256 i; i < pools.length; i++) {
            assertEq(allMarkets[i], pools[i]);
        }
    }

    function testGetMarketData() public {
        (
            uint256 supplyP2PIndex,
            uint256 borrowP2PIndex,
            uint256 lastUpdateBlockNumber,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        ) = marketsManager.getMarketData(cDai);

        assertEq(supplyP2PIndex, marketsManager.supplyP2PIndex(cDai));
        assertEq(borrowP2PIndex, marketsManager.borrowP2PIndex(cDai));
        assertEq(lastUpdateBlockNumber, marketsManager.lastUpdateBlockNumber(cDai));
        (
            uint256 supplyP2PDelta,
            uint256 borrowP2PDelta,
            uint256 supplyP2PAmount,
            uint256 borrowP2PAmount
        ) = positionsManager.deltas(cDai);

        assertEq(supplyP2PDelta_, supplyP2PDelta);
        assertEq(borrowP2PDelta_, borrowP2PDelta);
        assertEq(supplyP2PAmount_, supplyP2PAmount);
        assertEq(borrowP2PAmount_, borrowP2PAmount);
    }

    function testGetMarketConfiguration() public {
        (bool isCreated, bool noP2P, bool paused, uint256 reserveFactor) = marketsManager
        .getMarketConfiguration(cDai);

        assertTrue(isCreated == marketsManager.isCreated(cDai));
        assertTrue(noP2P == marketsManager.noP2P(cDai));
        assertTrue(paused == positionsManager.paused(cDai));
        assertTrue(reserveFactor == marketsManager.reserveFactor(cDai));
    }

    function testGetUpdatedP2PIndexes() public {
        hevm.warp(block.timestamp + (365 days));
        marketsManager.updateP2PIndexes(cDai);

        (uint256 newSupplyP2PIndex, uint256 newBorrowP2PIndex) = marketsManager
        .getUpdatedP2PIndexes(cDai);
        assertEq(newBorrowP2PIndex, marketsManager.borrowP2PIndex(cDai));
        assertEq(newSupplyP2PIndex, marketsManager.supplyP2PIndex(cDai));
    }
}
