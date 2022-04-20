// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./interfaces/IPositionsManagerForCompound.sol";
import "./interfaces/compound/ICompound.sol";

import "./libraries/LibMarketsManager.sol";
import "./libraries/CompoundMath.sol";
import "./libraries/LibStorage.sol";
import "./libraries/Types.sol";

/// @title MarketsManagerForCompound.
/// @notice Smart contract managing the markets used by a MorphoPositionsManagerForCompound contract, an other contract interacting with Compound or a fork of Compound.
contract MarketsManagerForCompound is WithStorageAndModifiers {
    using CompoundMath for uint256;

    /// EVENTS ///

    /// @notice Emitted when a `noP2P` variable is set.
    /// @param _poolTokenAddress The address of the market to set.
    /// @param _noP2P The new value of `_noP2P` adopted.
    event NoP2PSet(address indexed _poolTokenAddress, bool _noP2P);

    /// @notice Emitted when the `reserveFactor` is set.
    /// @param _poolTokenAddress The address of the market set.
    /// @param _newValue The new value of the `reserveFactor`.
    event ReserveFactorSet(address indexed _poolTokenAddress, uint256 _newValue);

    /// ERRORS ///

    /// @notice Thrown when the market is not created yet.
    error MarketNotCreated();

    /// MODIFIERS ///

    /// @notice Prevents to update a market not created yet.
    /// @param _poolTokenAddress The address of the market to check.
    modifier isMarketCreated(address _poolTokenAddress) {
        if (!ms().isCreated[_poolTokenAddress]) revert MarketNotCreated();
        _;
    }

    /// EXTERNAL ///

    /// @notice Creates a new market to borrow/supply in.
    /// @param _poolTokenAddress The pool token address of the given market.
    function createMarket(address _poolTokenAddress) external onlyOwner {
        LibMarketsManager.createMarket(_poolTokenAddress);
    }

    /// @notice Updates the P2P exchange rates, taking into account the Second Percentage Yield values.
    /// @param _poolTokenAddress The address of the market to update.
    function updateP2PExchangeRates(address _poolTokenAddress) external {
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
    }

    /// SETTERS ///

    /// @notice Sets the `reserveFactor`.
    /// @param _poolTokenAddress The market on which to set the `_newReserveFactor`.
    /// @param _newReserveFactor The proportion of the interest earned by users sent to the DAO, in basis point.
    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor)
        external
        onlyOwner
    {
        LibMarketsManager.updateP2PExchangeRates(_poolTokenAddress);
        ms().reserveFactor[_poolTokenAddress] = CompoundMath.min(
            MAX_BASIS_POINTS,
            _newReserveFactor
        );
        emit ReserveFactorSet(_poolTokenAddress, ms().reserveFactor[_poolTokenAddress]);
    }

    /// @notice Sets whether to match people P2P or not.
    /// @param _poolTokenAddress The address of the market.
    /// @param _noP2P Whether to match people P2P or not.
    function setNoP2P(address _poolTokenAddress, bool _noP2P)
        external
        onlyOwner
        isMarketCreated(_poolTokenAddress)
    {
        ms().noP2P[_poolTokenAddress] = _noP2P;
        emit NoP2PSet(_poolTokenAddress, _noP2P);
    }

    /// GETTERS ///

    /// @notice Returns all created markets.
    /// @return marketsCreated_ The list of market adresses.
    function getAllMarkets() external view returns (address[] memory marketsCreated_) {
        marketsCreated_ = ms().marketsCreated;
    }

    /// @notice Returns market's data.
    /// @return supplyP2PExchangeRate_ The supply P2P exchange rate of the market.
    /// @return borrowP2PExchangeRate_ The borrow P2P exchange rate of the market.
    /// @return lastUpdateBlockNumber_ The last block number when P2P exchange rates where updated.
    /// @return supplyP2PDelta_ The supply P2P delta (in scaled balance).
    /// @return borrowP2PDelta_ The borrow P2P delta (in cdUnit).
    /// @return supplyP2PAmount_ The supply P2P amount (in P2P unit).
    /// @return borrowP2PAmount_ The borrow P2P amount (in P2P unit).
    function getMarketData(address _poolTokenAddress)
        external
        view
        returns (
            uint256 supplyP2PExchangeRate_,
            uint256 borrowP2PExchangeRate_,
            uint256 lastUpdateBlockNumber_,
            uint256 supplyP2PDelta_,
            uint256 borrowP2PDelta_,
            uint256 supplyP2PAmount_,
            uint256 borrowP2PAmount_
        )
    {
        {
            Types.Delta memory delta = ps().deltas[_poolTokenAddress];
            supplyP2PDelta_ = delta.supplyP2PDelta;
            borrowP2PDelta_ = delta.borrowP2PDelta;
            supplyP2PAmount_ = delta.supplyP2PAmount;
            borrowP2PAmount_ = delta.borrowP2PAmount;
        }
        supplyP2PExchangeRate_ = ms().supplyP2PExchangeRate[_poolTokenAddress];
        borrowP2PExchangeRate_ = ms().borrowP2PExchangeRate[_poolTokenAddress];
        lastUpdateBlockNumber_ = ms().lastUpdateBlockNumber[_poolTokenAddress];
    }

    /// @notice Returns market's configuration.
    /// @return isCreated_ Whether the market is created or not.
    /// @return noP2P_ Whether user are put in P2P or not.
    function getMarketConfiguration(address _poolTokenAddress)
        external
        view
        returns (bool isCreated_, bool noP2P_)
    {
        isCreated_ = ms().isCreated[_poolTokenAddress];
        noP2P_ = ms().noP2P[_poolTokenAddress];
    }

    /// @notice Returns the updated P2P exchange rates.
    /// @param _poolTokenAddress The address of the market to update.
    /// @return newSupplyP2PExchangeRate The supply P2P exchange rate after udpate.
    /// @return newBorrowP2PExchangeRate The supply P2P exchange rate after udpate.
    function getUpdatedP2PExchangeRates(address _poolTokenAddress)
        external
        view
        returns (uint256 newSupplyP2PExchangeRate, uint256 newBorrowP2PExchangeRate)
    {
        return LibMarketsManager.getUpdatedP2PExchangeRates(_poolTokenAddress);
    }

    /// @notice Whether or not this market is created.
    function isCreated(address _market) external view returns (bool isCreated_) {
        isCreated_ = ms().isCreated[_market];
    }

    /// @notice Proportion of the interest earned by users sent to the DAO for each market, in basis point (100% = 10000). The default value is 0.
    function reserveFactor(address _market) external view returns (uint256 reserveFactor_) {
        reserveFactor_ = ms().reserveFactor[_market];
    }

    /// @notice Current exchange rate from supply p2pUnit to underlying (in wad).
    function supplyP2PExchangeRate(address _market)
        external
        view
        returns (uint256 supplyP2PExchangeRate_)
    {
        supplyP2PExchangeRate_ = ms().supplyP2PExchangeRate[_market];
    }

    /// @notice Current exchange rate from borrow p2pUnit to underlying (in wad).
    function borrowP2PExchangeRate(address _market)
        external
        view
        returns (uint256 borrowP2PExchangeRate_)
    {
        borrowP2PExchangeRate_ = ms().borrowP2PExchangeRate[_market];
    }

    /// @notice Last block number when P2P exchange rates where updated.
    function lastUpdateBlockNumber(address _market)
        external
        view
        returns (uint256 lastUpdateBlockNumber_)
    {
        lastUpdateBlockNumber_ = ms().lastUpdateBlockNumber[_market];
    }

    /// @notice Last pool index stored.
    function lastPoolIndexes(address _market)
        external
        view
        returns (Types.LastPoolIndexes memory lastPoolIndexes_)
    {
        lastPoolIndexes_ = ms().lastPoolIndexes[_market];
    }

    /// @notice Whether to put users on pool or not for the given market.
    function noP2P(address _market) external view returns (bool noP2P_) {
        noP2P_ = ms().noP2P[_market];
    }

    function comptroller() external view returns (IComptroller comptroller_) {
        comptroller_ = ms().comptroller;
    }
}
