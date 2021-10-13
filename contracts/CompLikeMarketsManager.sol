// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

import {ICErc20, IComptroller} from "./interfaces/ICompound.sol";
import "./interfaces/ICompLikePositionsManager.sol";

/**
 *  @title CompLikeMarketsManager
 *  @dev Smart contracts interacting with Compound-like protocol and its markets.
 */
contract CompLikeMarketsManager is Ownable {
    using PRBMathUD60x18 for uint256;
    using Math for uint256;

    /* Storage */

    bool public isPositionsManagerSet;
    mapping(address => bool) public isListed; // Whether or not this market is listed.
    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public p2pBPY; // Block Percentage Yield ("midrate").
    mapping(address => uint256) public mUnitExchangeRate; // current exchange rate from mUnit to underlying.
    mapping(address => uint256) public lastUpdateBlockNumber; // Last time mUnitExchangeRate was updated.
    mapping(address => uint256) public thresholds; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    ICompLikePositionsManager public compLikePositionsManager;

    /* Events */

    /** @dev Emitted when a new market is created.
     *  @param _marketAddress The address of the market that has been created.
     */
    event MarketCreated(address _marketAddress);

    /** @dev Emitted when a new market is listed.
     *  @param _marketAddress The address of the market that has been listed.
     */
    event MarketListed(address _marketAddress);

    /** @dev Emitted when a new market is listed.
     *  @param _marketAddress The address of the market that has been listed.
     */
    event MarketDelisted(address _marketAddress);

    /** @dev Emitted when the comptroller is set on the `compLikePositionsManager`.
     *  @param _comptrollerAddress The address of the comptroller proxy.
     */
    event ComptrollerSet(address _comptrollerAddress);

    /** @dev Emitted when the `compLikePositionsManager` is set.
     *  @param _compLikePositionsManagerAddress The address of the `compLikePositionsManager`.
     */
    event CompLikePositionsManagerSet(address _compLikePositionsManagerAddress);

    /** @dev Emitted when the p2pBPY of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the p2pBPY.
     */
    event BPYUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when the mUnitExchangeRate of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the mUnitExchangeRate.
     */
    event MUnitExchangeRateUpdated(address _marketAddress, uint256 _newValue);

    /** @dev Emitted when a threshold of a market is updated.
     *  @param _marketAddress The address of the market to update.
     *  @param _newValue The new value of the threshold.
     */
    event ThresholdUpdated(address _marketAddress, uint256 _newValue);

    /* Modifiers */

    /** @dev Prevents to update a market not created yet.
     */
    modifier isMarketCreated(address _marketAddress) {
        require(isCreated[_marketAddress], "mkt-not-created");
        _;
    }

    /* External */

    /** @dev Sets the `compLikePositionsManager` to interact with positions on Compound-like protocol.
     *  @param _compLikePositionsManager The address of position manager module.
     */
    function setCompLikePositionsManager(address _compLikePositionsManager) external onlyOwner {
        require(!isPositionsManagerSet, "positions-manager-already-set");
        isPositionsManagerSet = true;
        compLikePositionsManager = ICompLikePositionsManager(_compLikePositionsManager);
        emit CompLikePositionsManagerSet(_compLikePositionsManager);
    }

    /** @dev Sets the comptroller address.
     *  @param _proxyComptrollerAddress The address of Compound-like protocol's comptroller.
     */
    function setComptroller(address _proxyComptrollerAddress) external onlyOwner {
        compLikePositionsManager.setComptroller(_proxyComptrollerAddress);
        emit ComptrollerSet(_proxyComptrollerAddress);
    }

    /** @dev Creates new markets to borrow/supply.
     *  @param _marketAddresses The addresses of the markets to add (cToken).
     */
    function createMarkets(address[] calldata _marketAddresses) external onlyOwner {
        uint256[] memory results = compLikePositionsManager.createMarkets(_marketAddresses);
        for (uint256 i; i < _marketAddresses.length; i++) {
            require(results[i] == 0, "createMarkets:enter-mkt-fail");
            address _marketAddress = _marketAddresses[i];
            require(!isCreated[_marketAddress], "createMarkets:mkt-already-created");
            isCreated[_marketAddress] = true;
            mUnitExchangeRate[_marketAddress] = 1e18;
            lastUpdateBlockNumber[_marketAddress] = block.number;
            thresholds[_marketAddress] = 1e18;
            emit MarketCreated(_marketAddress);
            updateBPY(_marketAddress);
        }
    }

    /** @dev Sets a market as listed.
     *  @param _marketAddress The address of the market to list.
     */
    function listMarket(address _marketAddress) external onlyOwner isMarketCreated(_marketAddress) {
        isListed[_marketAddress] = true;
        emit MarketListed(_marketAddress);
    }

    /** @dev Sets a market as not listed.
     *  @param _marketAddress The address of the market to delist.
     */
    function delistMarket(address _marketAddress)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        isListed[_marketAddress] = false;
        emit MarketDelisted(_marketAddress);
    }

    /** @dev Updates thresholds below the ones suppliers and borrowers cannot enter markets.
     *  @param _marketAddress The address of the market to change the threshold.
     *  @param _newThreshold The new threshold to set.
     */
    function updateThreshold(address _marketAddress, uint256 _newThreshold) external onlyOwner {
        require(_newThreshold > 0, "updateThreshold:threshold!=0");
        thresholds[_marketAddress] = _newThreshold;
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /* Public */

    /** @dev Updates the Block Percentage Yield (`p2pBPY`) and calculate the current exchange rate (`mUnitExchangeRate`).
     *  @param _marketAddress The address of the market we want to update.
     */
    function updateBPY(address _marketAddress) public isMarketCreated(_marketAddress) {
        ICErc20 cErc20Token = ICErc20(_marketAddress);

        // Update p2pBPY
        uint256 supplyBPY = cErc20Token.supplyRatePerBlock();
        uint256 borrowBPY = cErc20Token.borrowRatePerBlock();
        p2pBPY[_marketAddress] = Math.average(supplyBPY, borrowBPY);

        emit BPYUpdated(_marketAddress, p2pBPY[_marketAddress]);

        // Update mUnitExhangeRate
        updateMUnitExchangeRate(_marketAddress);
    }

    /** @dev Updates the current exchange rate, taking into account the block percentage yield (p2pBPY) since the last time it has been updated.
     *  @param _marketAddress The address of the market we want to update.
     *  @return currentExchangeRate to convert from mUnit to underlying or from underlying to mUnit.
     */
    function updateMUnitExchangeRate(address _marketAddress)
        public
        isMarketCreated(_marketAddress)
        returns (uint256)
    {
        uint256 currentBlock = block.number;

        if (lastUpdateBlockNumber[_marketAddress] == currentBlock) {
            return mUnitExchangeRate[_marketAddress];
        } else {
            uint256 numberOfBlocksSinceLastUpdate = currentBlock -
                lastUpdateBlockNumber[_marketAddress];
            // Update lastUpdateBlockNumber
            lastUpdateBlockNumber[_marketAddress] = currentBlock;

            uint256 newMUnitExchangeRate = mUnitExchangeRate[_marketAddress].mul(
                (1e18 + p2pBPY[_marketAddress]).pow(
                    PRBMathUD60x18.fromUint(numberOfBlocksSinceLastUpdate)
                )
            );

            // Update currentExchangeRate
            mUnitExchangeRate[_marketAddress] = newMUnitExchangeRate;
            emit MUnitExchangeRateUpdated(_marketAddress, newMUnitExchangeRate);
            return newMUnitExchangeRate;
        }
    }
}
