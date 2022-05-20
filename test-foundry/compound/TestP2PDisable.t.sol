// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "hardhat/console.sol";

import "./setup/TestSetup.sol";

contract TestP2PDisable is TestSetup {
    function testShouldMatchSupplyDeltaWithP2PDisabled() public {
        uint256 nSuppliers = 3;
        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = nSuppliers * suppliedAmount;
        uint256 collateralAmount = 2 * borrowedAmount;

        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(cUsdc, to6Decimals(collateralAmount));
        borrower1.borrow(cDai, borrowedAmount);

        for (uint256 i; i < nSuppliers; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(cDai, suppliedAmount);
        }

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(cDai, type(uint256).max);

        // Delta must be greater than 0.
        (uint256 p2pSupplyDelta, , , ) = morpho.deltas(cDai);
        assertGt(p2pSupplyDelta, 0);

        // Disable peer-to-peer.
        morpho.toggleP2P(cDai);

        // Delta must be reduce to 0.
        borrower1.borrow(cDai, borrowedAmount);
        (p2pSupplyDelta, , , ) = morpho.deltas(cDai);
        testEquality(p2pSupplyDelta, 0);
    }

    function testShouldMatchBorrowDeltaWithP2PDisabled() public {
        uint256 nBorrowers = 3;
        uint256 borrowAmount = 1 ether;
        uint256 collateralAmount = 2 * borrowAmount;
        uint256 supplyAmount = nBorrowers * borrowAmount;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(cUsdc, to6Decimals(supplyAmount));

        for (uint256 i; i < nBorrowers; i++) {
            borrowers[i].approve(dai, type(uint256).max);
            borrowers[i].approve(usdc, type(uint256).max);
            borrowers[i].supply(cDai, collateralAmount);
            borrowers[i].borrow(cUsdc, to6Decimals(borrowAmount));
        }

        // Create delta.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 0, 3e6);
        supplier1.withdraw(cUsdc, to6Decimals(supplyAmount));

        // Delta must be greater than 0.
        (, uint256 p2pBorrowDelta, , ) = morpho.deltas(cUsdc);
        assertGt(p2pBorrowDelta, 0);

        // Disable peer-to-peer.
        morpho.toggleP2P(cUsdc);

        // Delta must be reduce to 0.
        supplier1.supply(cUsdc, to6Decimals(supplyAmount * 2));
        (, p2pBorrowDelta, , ) = morpho.deltas(cUsdc);
        testEquality(p2pBorrowDelta, 0);
    }
}
