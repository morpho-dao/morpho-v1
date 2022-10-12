// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using WadRayMath for uint256;

    function testShouldDeployContractWithTheRightValues() public {
        assertEq(address(morpho.entryPositionsManager()), address(entryPositionsManager));
        assertEq(address(morpho.exitPositionsManager()), address(exitPositionsManager));
        assertEq(address(morpho.interestRatesManager()), address(interestRatesManager));
        assertEq(address(morpho.addressesProvider()), address(poolAddressesProvider));
        assertEq(address(morpho.pool()), poolAddressesProvider.getLendingPool());
        assertEq(morpho.maxSortedUsers(), 20);

        (uint256 supply, uint256 borrow, uint256 withdraw, uint256 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, 3e6);
        assertEq(borrow, 3e6);
        assertEq(withdraw, 3e6);
        assertEq(repay, 3e6);
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        morpho.createMarket(address(supplier1), 3_333, 0);
    }

    function testOnlyOwnerCanCreateMarkets() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.createMarket(wEth, 3_333, 0);

        morpho.createMarket(wEth, 3_333, 0);
    }

    function testShouldCreateMarketWithRightParams() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, 10_001, 0);
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, 0, 10_001);

        morpho.createMarket(wEth, 1_000, 3_333);
        (address underlyingToken, uint16 reserveFactor, uint256 p2pIndexCursor, , , , ) = morpho
        .market(aWeth);
        assertEq(reserveFactor, 1_000);
        assertEq(p2pIndexCursor, 3_333);
        assertTrue(underlyingToken == wEth);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(aDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(aDai, 1111);
        }

        morpho.setReserveFactor(aDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        morpho.setReserveFactor(aDai, 1111);
        (, uint16 reserveFactor, , , , , ) = morpho.market(aDai);
        assertEq(reserveFactor, 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        morpho.createMarket(wEth, 3_333, 0);

        (, , , bool isCreated, , , ) = morpho.market(aWeth);

        assertTrue(isCreated);
        assertEq(morpho.p2pSupplyIndex(aWeth), WadRayMath.RAY);
        assertEq(morpho.p2pBorrowIndex(aWeth), WadRayMath.RAY);
    }

    function testShouldSetMaxGasWithRightValues() public {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: 1,
            borrow: 1,
            withdraw: 1,
            repay: 1
        });

        morpho.setDefaultMaxGasForMatching(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setDefaultMaxGasForMatching(newMaxGas);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setDefaultMaxGasForMatching(newMaxGas);
    }

    function testOnlyOwnerCanSetMaxSortedUsers() public {
        uint256 newMaxSortedUsers = 30;

        morpho.setMaxSortedUsers(newMaxSortedUsers);
        assertEq(morpho.maxSortedUsers(), newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setMaxSortedUsers(newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setMaxSortedUsers(newMaxSortedUsers);
    }

    function testOnlyOwnerShouldFlipMarketStrategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        hevm.prank(address(supplier1));
        morpho.setP2PDisabledStatus(aDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        hevm.prank(address(supplier2));
        morpho.setP2PDisabledStatus(aDai, true);

        morpho.setP2PDisabledStatus(aDai, true);
        (, , , , , , bool isP2PDisabled) = morpho.market(aDai);
        assertTrue(isP2PDisabled);
    }

    function testOnlyOwnerShouldSetEntryPositionsManager() public {
        IEntryPositionsManager entryPositionsManagerV2 = new EntryPositionsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setEntryPositionsManager(entryPositionsManagerV2);

        morpho.setEntryPositionsManager(entryPositionsManagerV2);
        assertEq(address(morpho.entryPositionsManager()), address(entryPositionsManagerV2));
    }

    function testOnlyOwnerShouldSetRewardsManager() public {
        IRewardsManager rewardsManagerV2 = new RewardsManagerOnMainnetAndAvalanche();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setRewardsManager(rewardsManagerV2);

        morpho.setRewardsManager(rewardsManagerV2);
        assertEq(address(morpho.rewardsManager()), address(rewardsManagerV2));
    }

    function testOnlyOwnerShouldSetInterestRatesManager() public {
        IInterestRatesManager interestRatesV2 = new InterestRatesManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setInterestRatesManager(interestRatesV2);

        morpho.setInterestRatesManager(interestRatesV2);
        assertEq(address(morpho.interestRatesManager()), address(interestRatesV2));
    }

    function testOnlyOwnerShouldSetIncentivesVault() public {
        IIncentivesVault incentivesVaultV2 = new IncentivesVault(
            IMorpho(address(morpho)),
            morphoToken,
            ERC20(address(1)),
            address(2),
            dumbOracle
        );

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIncentivesVault(incentivesVaultV2);

        morpho.setIncentivesVault(incentivesVaultV2);
        assertEq(address(morpho.incentivesVault()), address(incentivesVaultV2));
    }

    function testOnlyOwnerShouldSetTreasuryVault() public {
        address treasuryVaultV2 = address(2);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setTreasuryVault(treasuryVaultV2);

        morpho.setTreasuryVault(treasuryVaultV2);
        assertEq(address(morpho.treasuryVault()), treasuryVaultV2);
    }

    function testOnlyOwnerCanSetClaimRewardsStatus() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setClaimRewardsPauseStatus(true);

        morpho.setClaimRewardsPauseStatus(true);
        assertTrue(morpho.isClaimRewardsPaused());
    }

    function testOnlyOwnerCanSetPauseStatusForAllMarkets() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setPauseStatusForAllMarkets(true);

        morpho.setPauseStatusForAllMarkets(true);
    }
}
