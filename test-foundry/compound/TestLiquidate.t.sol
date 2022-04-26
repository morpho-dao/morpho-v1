// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using CompoundMath for uint256;

    // 5.1 - A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("DebtValueNotAboveMax()"));
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);
    }

    // 5.2 - A user liquidates a borrower that has not enough collateral to cover for his debt.
    function testShouldLiquidateUser() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        (, uint256 amount) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 94) / 100);

        // Liquidate.
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(positionsManager), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = toRepay.div(ICToken(cDai).borrowIndex());
        assertApproxEq(onPoolBorrower, expectedBorrowBalanceOnPool, 5, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(inP2PBorrower, 0, "borrower supply in P2P");
    }

    function testShouldLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );
        (, uint256 supplierDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            cDai
        );

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = positionsManager.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = positionsManager.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 2) - 1; // -1 because of rounding error related to compound's approximation
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) +
            inP2PUsdc.mul(marketsManager.borrowP2PExchangeRate(cUsdc)) -
            (borrowerDebt / 2);

        assertEq(onPoolBorrower, 0, "borrower borrow on pool");
        assertApproxEq(
            inP2PBorrower.mul(marketsManager.borrowP2PExchangeRate(cUsdc)),
            expectedBorrowBalanceInP2P,
            2,
            "borrower borrow in P2P"
        );

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        assertEq(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in P2P");
    }

    function testShouldPartiallyLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cUsdc
        );
        (, uint256 supplierDebt) = positionsManager.getUserMaxCapacitiesForAsset(
            address(supplier1),
            cDai
        );

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = positionsManager.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = positionsManager.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 4);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = positionsManager.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceOnPool = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) -
            toRepay;

        assertApproxEq(
            onPoolBorrower.mul(ICToken(cUsdc).borrowIndex()),
            expectedBorrowBalanceOnPool,
            1,
            "borrower borrow on pool"
        );
        assertEq(inP2PBorrower, inP2PUsdc, "borrower borrow in P2P");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = positionsManager.supplyBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        assertEq(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        assertEq(inP2PBorrower, inP2PDai, "borrower supply in P2P");
    }

    function testFailLiquidateZero() public {
        positionsManager.liquidate(cDai, cDai, cDai, 0);
    }
}
