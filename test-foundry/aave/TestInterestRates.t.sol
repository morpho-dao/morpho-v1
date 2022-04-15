// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestInterestRates is TestSetup {
    function testExchangeRateComputation() public {
        Types.Params memory params = Types.Params(
            1 * RAY, // supplyP2PExchangeRate;
            1 * RAY, // borrowP2PExchangeRate
            2 * RAY, // poolSupplyExchangeRate;
            3 * RAY, // poolBorrowExchangeRate;
            1 * RAY, // lastPoolSupplyExchangeRate;
            1 * RAY, // lastPoolBorrowExchangeRate;
            0, // reserveFactor;
            Types.Delta(0, 0, 0, 0) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, (7 * RAY) / 3);
        assertEq(newBorrowP2PExchangeRate, (7 * RAY) / 3);
    }

    function testExchangeRateComputationWithReserveFactor() public {
        Types.Params memory params = Types.Params(
            1 * RAY, // supplyP2PExchangeRate;
            1 * RAY, // borrowP2PExchangeRate
            2 * RAY, // poolSupplyExchangeRate;
            3 * RAY, // poolBorrowExchangeRate;
            1 * RAY, // lastPoolSupplyExchangeRate;
            1 * RAY, // lastPoolBorrowExchangeRate;
            5_000, // reserveFactor;
            Types.Delta(0, 0, 0, 0) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertApproxEq(
            newSupplyP2PExchangeRate,
            ((2 * 2 + 1 * 3) * RAY) / 3 / 2 + (2 * RAY) / 2,
            1
        );
        assertApproxEq(
            newBorrowP2PExchangeRate,
            ((2 * 2 + 1 * 3) * RAY) / 3 / 2 + (3 * RAY) / 2,
            1
        );
    }

    function testExchangeRateComputationWithDelta() public {
        Types.Params memory params = Types.Params(
            1 * RAY, // supplyP2PExchangeRate;
            1 * RAY, // borrowP2PExchangeRate
            2 * RAY, // poolSupplyExchangeRate;
            3 * RAY, // poolBorrowExchangeRate;
            1 * RAY, // lastPoolSupplyExchangeRate;
            1 * RAY, // lastPoolBorrowExchangeRate;
            0, // reserveFactor;
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertApproxEq(newSupplyP2PExchangeRate, ((7 * RAY) / 3 + 2 * RAY) / 2, 1);
        assertApproxEq(newBorrowP2PExchangeRate, ((7 * RAY) / 3 + 3 * RAY) / 2, 1);
    }

    function testExchangeRateComputationWithDeltaAndReserveFactor() public {
        Types.Params memory params = Types.Params(
            1 * RAY, // supplyP2PExchangeRate;
            1 * RAY, // borrowP2PExchangeRate
            2 * RAY, // poolSupplyExchangeRate;
            3 * RAY, // poolBorrowExchangeRate;
            1 * RAY, // lastPoolSupplyExchangeRate;
            1 * RAY, // lastPoolBorrowExchangeRate;
            5_000, // reserveFactor;
            Types.Delta(1 * WAD, 1 * WAD, 4 * WAD, 6 * WAD) // delta;
        );

        (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate) = interestRates
        .computeP2PExchangeRates(params);

        assertEq(newSupplyP2PExchangeRate, (((7 * RAY) / 3 + 2 * RAY) / 2 + 2 * RAY) / 2);
        assertEq(newBorrowP2PExchangeRate, (((7 * RAY) / 3 + 3 * RAY) / 2 + 3 * RAY) / 2);
    }
}
