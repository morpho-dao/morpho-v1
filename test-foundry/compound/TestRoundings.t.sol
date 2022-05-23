// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestRounding is TestSetup {
    using CompoundMath for uint256;

    // This test compares balances stored by Compound & amount passed in argument.
    // The back & forth to cUnits leads to loss of information (when the underlying has enough decimals).
    function testRoundingError1() public {
        uint256 amountSupplied = 1e18;

        // Supplier1 supplies 1 Dai.
        supplier1.approve(dai, amountSupplied);
        supplier1.supply(cDai, amountSupplied);

        // Compare balances in underlying units.
        uint256 balanceOnCompInUnderlying = ICToken(cDai).balanceOfUnderlying(address(morpho));
        assertFalse(balanceOnCompInUnderlying == amountSupplied, "comparison in underlying units");

        // Previous test returns the following
        /*
        Logs:
        Error: comparison in underlying units
        Error: a == b not satisfied [uint]
            Expected: 1000000000000000000
            Actual: 999999999988707085
        */
    }

    // This test shows that small balances are discarded if amount is inferior to 1e8
    // (given enough decimals on the underlying) due to the division & multiplication with the index.
    function testRoundingError2() public {
        uint256 amountSupplied = 1e5;

        // Supplier1 supplies 1 Dai.
        supplier1.approve(dai, amountSupplied);
        supplier1.supply(cDai, amountSupplied);

        // Compare balances in underlying units.
        uint256 balanceOnCompInUnderlying = ICToken(cDai).balanceOfUnderlying(address(morpho));
        assertFalse(balanceOnCompInUnderlying == amountSupplied, "comparison in underlying units");

        // Previous test returns the following
        /*
        Logs:
        Error: comparison in underlying units
        Error: a == b not satisfied [uint]
            Expected: 100000
            Actual: 0
        */
    }

    // Calling compound function with 0 as parameter doesn't generate an error, function isn't executed.
    // However, some underlying amounts can turn out to be null when expressed in cToken units (see testRoundingError2).
    // Still, the function is executed. mint, borrow, repayBorrow are fine, but redeemUnderlying reverts.
    function testRoundingError3() public {
        tip(dai, address(this), 1e20);
        ERC20(dai).approve(cDai, type(uint64).max);

        // mint 1 cDai, doesn't revert
        ICToken(cDai).mint(1);

        // borrow 1 cDai, doesn't revert
        ICToken(cDai).mint(1e18);
        ICToken(cDai).borrow(1);

        // repay 1 cDai, doesn't revert
        ICToken(cDai).repayBorrow(1);

        // redeem 1 cDai, it DOES revert
        hevm.expectRevert("redeemTokens zero");
        ICToken(cDai).redeemUnderlying(1);

        // Previous test returns the following
        /*
        [31m[FAIL. Reason: redeemTokens zero][0m testRoundingError3() (gas: 742070)
        */
    }

    // Check rounding on supply
    function testRoundingError4() public {
        supplier1.approve(dai, 1 ether);
        supplier1.supply(cDai, 1 ether);

        uint256 balanceByComp = ICToken(cDai).balanceOfUnderlying(address(morpho));
        (, , uint256 balanceByLens) = lens.getUserSupplyBalance(address(supplier1), cDai);

        assertEq(balanceByComp, balanceByLens);
    }

    // Check rounding on borrow
    function testRoundingError5() public {
        supplier1.approve(wEth, 1 ether);
        supplier1.supply(cEth, 1 ether);
        supplier1.borrow(cDai, 1 ether);

        uint256 balanceByComp = ICToken(cDai).borrowBalanceCurrent(address(morpho));
        (, , uint256 balanceByLens) = lens.getUserBorrowBalance(address(supplier1), cDai);

        assertEq(balanceByComp, balanceByLens);
    }

    // Check rounding on repay
    function testRoundingError6() public {
        supplier1.approve(wEth, 1 ether);
        supplier1.supply(cEth, 1 ether);
        supplier1.borrow(cDai, 1 ether);

        supplier1.approve(dai, 1 ether / 2);
        supplier1.repay(cDai, 1 ether / 2);

        uint256 balanceByComp = ICToken(cDai).borrowBalanceCurrent(address(morpho));
        (, , uint256 balanceByLens) = lens.getUserBorrowBalance(address(supplier1), cDai);

        assertEq(balanceByComp, balanceByLens);
    }

    // Check rounding on withdraw
    function testRoundingError7() public {
        supplier1.approve(dai, 1 ether);
        supplier1.supply(cDai, 1 ether);

        supplier1.withdraw(cDai, 1 ether / 2);

        uint256 balanceByComp = ICToken(cDai).balanceOfUnderlying(address(morpho));
        (, , uint256 balanceByLens) = lens.getUserSupplyBalance(address(supplier1), cDai);

        assertEq(balanceByComp, balanceByLens);
    }

    // Demonstrate borrow balance approximation issue
    function testRoundingError8() public {
        ICompoundOracle oracle = ICompoundOracle(morpho.comptroller().oracle());

        uint256 amountCollateral = 42615668125821;
        uint256 borrowUsdc = 89;
        uint256 borrowEth = 45856658344;

        supplier1.approve(uni, amountCollateral);
        supplier1.supply(cUni, amountCollateral);
        supplier1.borrow(cUsdc, borrowUsdc);

        uint256 balanceByComp = ICToken(cUsdc).borrowBalanceCurrent(address(morpho));
        (, , uint256 balanceByLens) = lens.getUserBorrowBalance(address(supplier1), cUsdc);
        // Logs:
        //   balanceByComp, 89
        //   balanceByLens, 88

        (uint256 withdrawable, uint256 borrowable) = lens.getUserMaxCapacitiesForAsset(
            address(supplier1),
            cEth
        );
        // Logs:
        //   withdrawable, 0
        //   borrowable, 75517313172

        // compute borrowable value with the correct borrow balance
        (, , uint256 newPoolSupplyIndex, ) = lens.getUpdatedIndexes(cUni);
        (, uint256 collateralFactor, ) = morpho.comptroller().markets(cUni);
        (, uint256 uniBalance) = morpho.supplyBalanceInOf(cUni, address(supplier1));
        uint256 collateralValue = uniBalance.mul(newPoolSupplyIndex).mul(collateralFactor).mul(
            oracle.getUnderlyingPrice(cUni)
        );
        // BalanceByComp user here instead of the borrow balance used in lens
        uint256 debtValue = balanceByComp.mul(oracle.getUnderlyingPrice(cUsdc));

        uint256 borrowableComputed = (collateralValue - debtValue).div(
            oracle.getUnderlyingPrice(cEth)
        );
        // Logs:
        //   borrowableComputed, 75134956945
        //   borrowable, 75517313172
        //   Exageration of borrowable by lens, 382356227

        hevm.expectRevert(abi.encodeWithSignature("BorrowOnCompoundFailed()"));
        supplier1.borrow(cEth, borrowable);
        // borrowableComputed is the exact max borrowable value:
        // Borrow passes for borrowableComputed and doesn't for borrowableComputed + 1.
    }
}
