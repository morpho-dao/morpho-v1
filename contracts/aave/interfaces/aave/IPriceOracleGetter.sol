pragma solidity 0.8.7;

/************
@title IPriceOracleGetter interface
@notice Interface for the Aave price oracle.*/
interface IPriceOracleGetter {
    /***********
    @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) external view returns (uint256);
}
