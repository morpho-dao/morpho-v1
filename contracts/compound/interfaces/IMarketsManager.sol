// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IMarketsManager {
    function marketStatuses(address)
        external
        view
        returns (
            bool,
            bool,
            bool
        );

    function p2pSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function p2pBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedp2pSupplyIndex(address _poolTokenAddress) external view returns (uint256);

    function getUpdatedp2pBorrowIndex(address _poolTokenAddress) external view returns (uint256);

    function updateP2PIndexes(address _marketAddress) external;

    function getUpdatedP2PIndexes(address _poolTokenAddress)
        external
        view
        returns (uint256, uint256);

    function isMarketCreatedAndNotPaused(address _poolTokenAddress) external view;

    function isMarketCreatedAndNotPausedOrPartiallyPaused(address _poolTokenAddress) external view;

    function isMarketCreated(address _poolTokenAddress) external view;
}
