// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../interfaces/IOracle.sol";

import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract IncentivesVault is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    address public immutable positionsManager; // The address of the Positions Manager.
    address public immutable morphoToken; // The address of the MORPHO token.
    address public morphoDao; // The address of the Morpho DAO treasury.
    address public oracle; // Thre oracle used to get the price of the pair MORPHO/COMP 🦋.
    uint256 public bonus; // The bonus of MORPHO tokens to give to the user as a percentage to add on top of the consulted amount on the oracle (in basis point).
    bool public isPaused; // Whether the swith of COMP rewards to MORPHO rewards is paused or not.

    /// EVENTS ///

    /// @notice Emitted when the oracle is set.
    event OracleSet(address _newOracle);

    /// @notice Emitted when the Morpho DAO is set.
    event MorphoDaoSet(address _newMorphoDao);

    /// @notice Emitted when the reward bonus is set.
    event BonusSet(uint256 _newBonus);

    /// @notice Emitted when the pause status is changed.
    event PauseStatusChanged(bool _newStatus);

    /// @notice Emitted when MORPHO tokens are transferred to the DAO.
    event MorphoTokensTransferred(uint256 _amount);

    /// @notice Emitted when COMP tokens are switched to MORPHO tokens.
    /// @param _receiver The address of the receiver.
    /// @param _compAmount The amount of COMP switched.
    /// @param _morphoAmount The amount of MORPHO sent.
    event CompTokensSwitched(address indexed _receiver, uint256 _compAmount, uint256 _morphoAmount);

    /// ERRROS ///

    /// @notice Thrown when only the posiyions manager can trigger the function.
    error OnlyPositionsManager();

    /// @notice Thrown when the vault is paused.
    error VaultIsPaused();

    /// CONSTRUCTOR ///

    /// @notice Constructs the IncentivesVault contract.
    /// @param _positionsManager The address of the Positions Manager.
    /// @param _morphoToken The address of the MORPHO token.
    /// @param _morphoDao The address of the Morpho DAO.
    /// @param _oracle The adress of the oracle.
    constructor(
        address _positionsManager,
        address _morphoToken,
        address _morphoDao,
        address _oracle
    ) {
        positionsManager = _positionsManager;
        morphoToken = _morphoToken;
        morphoDao = _morphoDao;
        oracle = _oracle;
    }

    /// EXTERNAL ///

    /// @notice Sets the oracle.
    /// @param _newOracle The address of the new oracle.
    function setOracle(address _newOracle) external onlyOwner {
        oracle = _newOracle;
        emit OracleSet(_newOracle);
    }

    /// @notice Sets the morho DAO.
    /// @param _newMorphoDao The address of the Morpho DAO.
    function setMorphoDao(address _newMorphoDao) external onlyOwner {
        morphoDao = _newMorphoDao;
        emit MorphoDaoSet(_newMorphoDao);
    }

    /// @notice Sets the reward bonus.
    /// @param _newBonus The new reward bonus.
    function setBonus(uint256 _newBonus) external onlyOwner {
        bonus = _newBonus;
        emit BonusSet(_newBonus);
    }

    /// @notice Toggles the pause status.
    function togglePauseStatus() external onlyOwner {
        bool newStatus = !isPaused;
        isPaused = newStatus;
        emit PauseStatusChanged(newStatus);
    }

    /// @notice Transfers the MORPHO tokens to the DAO.
    /// @param _amount The amount of MORPHO tokens to transfer to the DAO.
    function transferMorphoTokensToDao(uint256 _amount) external onlyOwner {
        ERC20(morphoToken).transfer(morphoDao, _amount);
        emit MorphoTokensTransferred(_amount);
    }

    /// @notice Trades COMP tokens for MORPHO tokens and sends them to the receiver.
    /// @param _receiver The address of the receiver.
    /// @param _amount The amount to transfer to the receiver.
    function tradeCompForMorphoTokens(address _receiver, uint256 _amount) external {
        if (msg.sender != positionsManager) revert OnlyPositionsManager();
        if (!isPaused) revert VaultIsPaused();

        // Transfer COMP to the DAO.
        ERC20(COMP).safeTransferFrom(msg.sender, morphoDao, _amount);

        // Add a bonus on MORPHO rewards.
        uint256 amountOut = (IOracle(oracle).consult(_amount) * (MAX_BASIS_POINTS + bonus)) /
            MAX_BASIS_POINTS;
        ERC20(morphoToken).transfer(_receiver, amountOut);

        emit CompTokensSwitched(_receiver, _amount, amountOut);
    }
}
