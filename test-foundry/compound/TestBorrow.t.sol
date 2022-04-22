// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";
import "@contracts/compound/positions-manager-parts/PositionsManagerEventsErrors.sol";

contract TestBorrow is TestSetup {
    using FixedPointMathLib for uint256;
    using CompoundMath for uint256;

    uint256 private MAX_BORROWABLE_DAI = uint256(7052532865252195763) / 2; // approx, taken from market conditions

    function testBorrow1() public {
        uint256 usdcAmount = to6Decimals(10_000 ether);

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(cUsdc, usdcAmount);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        hevm.expectRevert(PositionsManagerGetters.DebtValueAboveMax.selector);
        borrower1.borrow(cDai, borrowable + 1e12);
    }

    function testFailBorrow1Fuzzed(uint256 supplied, uint256 borrowed) public {
        hevm.assume(supplied != 0 && supplied < INITIAL_BALANCE * 1e6 && borrowed != 0);
        uint256 usdcAmount = supplied;

        borrower1.approve(usdc, usdcAmount);
        borrower1.supply(cUsdc, usdcAmount);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );

        hevm.assume(borrowed > borrowable);

        borrower1.borrow(cDai, borrowed);
    }

    // sould borrow an authorized amount of dai after having provided some usdc
    function testBorrowFuzzed(uint256 amountSupplied, uint256 amountBorrowed) public {
        console.log(ERC20(usdc).balanceOf(address(borrower1)));

        hevm.assume(
            amountSupplied != 0 && amountSupplied < INITIAL_BALANCE * 1e6 && amountBorrowed != 0
        );

        borrower1.approve(usdc, amountSupplied);
        borrower1.supply(cUsdc, amountSupplied);

        (, uint256 borrowable) = positionsManager.getUserMaxCapacitiesForAsset(
            address(borrower1),
            cDai
        );
        hevm.assume(amountBorrowed <= borrowable && amountBorrowed <= MAX_BORROWABLE_DAI);

        borrower1.borrow(cDai, amountBorrowed);
    }

    function testBorrow2() public {
        uint256 amount = 10000 ether;

        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(cUsdc, to6Decimals(2 * amount));
        borrower1.borrow(cDai, amount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedOnPool = amount.div(ICToken(cDai).borrowIndex());

        assertEq(onPool, expectedOnPool);
        assertEq(inP2P, 0);
    }

    function testBorrow3() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(amount * 2));
        borrower1.supply(cUsdc, to6Decimals(amount * 2));

        uint256 cDaiExchangeRate = ICToken(cDai).exchangeRateCurrent();
        (, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
        uint256 toBorrow = supplyOnPool.mul(cDaiExchangeRate);
        borrower1.borrow(cDai, toBorrow);

        (uint256 supplyInP2P, ) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));

        uint256 borrowP2PExchangeRate = marketsManager.borrowP2PExchangeRate(cDai);
        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiExchangeRate).div(
            borrowP2PExchangeRate
        );
        uint256 expectedSupplyInP2P = expectedBorrowInP2P;

        assertEq(supplyInP2P, expectedSupplyInP2P, "Supplier1 in P2P");

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        assertEq(onPool, 0, "Borrower1 on pool");
        assertEq(inP2P, expectedBorrowInP2P, "Borrower1 in P2P");
    }

    function testBorrow4() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(usdc, to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));
        uint256 borrowAmount = amount * 2;

        uint256 cDaiExchangeRate = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, borrowAmount);

        (uint256 inP2P, uint256 onPool) = positionsManager.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiExchangeRate).div(
            marketsManager.borrowP2PExchangeRate(cDai)
        );
        uint256 expectedBorrowOnPool = (borrowAmount -
            getBalanceOnCompound(amount, cDaiExchangeRate))
        .div(ICToken(cDai).borrowIndex());

        assertEq(inP2P, expectedBorrowInP2P, "Borrower1 in P2P");
        assertEq(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    function testBorrow5() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / NMAX;
        uint256[] memory rates = new uint256[](NMAX);
        uint256 toBorrow;

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);

            (, uint256 supplyOnPool) = positionsManager.supplyBalanceInOf(cDai, address(supplier1));
            toBorrow += supplyOnPool.mul(rates[i]);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiExchangeRate = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, toBorrow);
        uint256 supplyP2PExchangeRate = marketsManager.supplyP2PExchangeRate(cDai);
        uint256 inP2P;
        uint256 onPool;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(supplyP2PExchangeRate),
                "in P2P"
            );
            assertEq(onPool, 0, "on pool");
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount, cDaiExchangeRate).div(
            marketsManager.borrowP2PExchangeRate(cDai)
        );

        assertApproxEq(inP2P, expectedBorrowInP2P, 1, "Borrower1 in P2P");
        assertEq(onPool, 0, "Borrower1 on pool");
    }

    function testBorrow6() public {
        setMaxGasHelper(type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max);

        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        uint8 NMAX = 5;
        createSigners(NMAX);

        uint256 amountPerSupplier = amount / (2 * NMAX);
        uint256[] memory rates = new uint256[](NMAX);

        for (uint256 i = 0; i < NMAX; i++) {
            // Rates change every time.
            rates[i] = ICToken(cDai).exchangeRateCurrent();
            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        uint256 cDaiExchangeRate = ICToken(cDai).exchangeRateCurrent();
        borrower1.borrow(cDai, amount);

        uint256 inP2P;
        uint256 onPool;
        uint256 borrowIndex = ICToken(cDai).borrowIndex();
        uint256 matchedAmount;

        for (uint256 i = 0; i < NMAX; i++) {
            (inP2P, onPool) = positionsManager.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(
                    marketsManager.supplyP2PExchangeRate(cDai)
                ),
                "in P2P"
            );
            assertEq(onPool, 0, "on pool");

            matchedAmount += getBalanceOnCompound(amountPerSupplier, cDaiExchangeRate);
        }

        (inP2P, onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowInP2P = getBalanceOnCompound(amount / 2, cDaiExchangeRate).div(
            marketsManager.borrowP2PExchangeRate(cDai)
        );
        uint256 expectedBorrowOnPool = (amount - matchedAmount).div(borrowIndex);

        assertApproxEq(inP2P, expectedBorrowInP2P, 5, "Borrower1 in P2P");
        assertEq(onPool, expectedBorrowOnPool, "Borrower1 on pool");
    }

    function testBorrowMultipleAssets() public {
        uint256 amount = 10_000 ether;

        borrower1.approve(usdc, address(positionsManager), to6Decimals(4 * amount));
        borrower1.supply(cUsdc, to6Decimals(4 * amount));

        borrower1.borrow(cDai, amount);
        borrower1.borrow(cDai, amount);

        (, uint256 onPool) = positionsManager.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedOnPool = (2 * amount).div(ICToken(cDai).borrowIndex());
        assertEq(onPool, expectedOnPool);
    }
}
