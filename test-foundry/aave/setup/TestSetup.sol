// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@contracts/aave/interfaces/aave/IAaveIncentivesController.sol";
import "@contracts/aave/interfaces/aave/IPriceOracleGetter.sol";
import "@contracts/aave/interfaces/aave/IProtocolDataProvider.sol";
import "@contracts/aave/interfaces/IRewardsManagerForAave.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "hardhat/console.sol";
import "../../common/helpers/Chains.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {RewardsManagerForAaveOnMainnetAndAvalanche} from "@contracts/aave/rewards-managers/RewardsManagerForAaveOnMainnetAndAvalanche.sol";
import {RewardsManagerForAaveOnPolygon} from "@contracts/aave/rewards-managers/RewardsManagerForAaveOnPolygon.sol";
import {SwapManagerUniV3OnMainnet} from "@contracts/common/SwapManagerUniV3OnMainnet.sol";
import {SwapManagerUniV3} from "@contracts/common/SwapManagerUniV3.sol";
import {SwapManagerUniV2} from "@contracts/common/SwapManagerUniV2.sol";
import "../../common/uniswap/UniswapV3PoolCreator.sol";
import "../../common/uniswap/UniswapV2PoolCreator.sol";
import "@contracts/aave/PositionsManagerForAave.sol";
import "@contracts/aave/MarketsManagerForAave.sol";
import "@contracts/aave/MatchingEngineForAave.sol";
import "@contracts/aave/InterestRatesV1.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/SimplePriceOracle.sol";
import {User} from "../../common/helpers/User.sol";
import {Utils} from "./Utils.sol";
import "forge-std/stdlib.sol";

import "@config/Config.sol";

contract TestSetup is Config, Utils, stdCheats {
    using SafeERC20 for IERC20;
    using Math for uint256;

    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public positionsManagerProxy;
    TransparentUpgradeableProxy public marketsManagerProxy;

    MatchingEngineForAave internal matchingEngine;
    PositionsManagerForAave internal positionsManagerImplV1;
    PositionsManagerForAave internal positionsManager;
    PositionsManagerForAave internal fakePositionsManagerImpl;
    MarketsManagerForAave internal marketsManager;
    MarketsManagerForAave internal marketsManagerImplV1;
    IRewardsManagerForAave internal rewardsManager;
    IInterestRates internal interestRates;
    ISwapManager public swapManager;
    UniswapV3PoolCreator public uniswapV3PoolCreator;
    UniswapV2PoolCreator public uniswapV2PoolCreator;
    MorphoToken public morphoToken;
    address public REWARD_TOKEN =
        IAaveIncentivesController(aaveIncentivesControllerAddress).REWARD_TOKEN();

    ILendingPoolAddressesProvider public lendingPoolAddressesProvider;
    ILendingPool public lendingPool;
    IProtocolDataProvider public protocolDataProvider;
    IPriceOracleGetter public oracle;

    User public supplier1;
    User public supplier2;
    User public supplier3;
    User[] public suppliers;

    User public borrower1;
    User public borrower2;
    User public borrower3;
    User[] public borrowers;
    User public treasuryVault;

    address[] public pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();
    }

    function initContracts() internal {
        PositionsManagerForAave.MaxGas memory maxGas = PositionsManagerForAaveStorage.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        lendingPoolAddressesProvider = ILendingPoolAddressesProvider(
            lendingPoolAddressesProviderAddress
        );
        lendingPool = ILendingPool(lendingPoolAddressesProvider.getLendingPool());

        interestRates = new InterestRatesV1();

        if (block.chainid == Chains.ETH_MAINNET) {
            // Mainnet network.
            // Create a MORPHO / WETH pool.
            uniswapV3PoolCreator = new UniswapV3PoolCreator();
            tip(uniswapV3PoolCreator.WETH9(), address(uniswapV3PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV3PoolCreator));
            swapManager = new SwapManagerUniV3OnMainnet(
                address(morphoToken),
                MORPHO_UNIV3_FEE,
                1 hours,
                1 hours
            );
        } else if (block.chainid == Chains.POLYGON_MAINNET) {
            // Polygon network.
            // Create a MORPHO / WMATIC pool.
            uniswapV3PoolCreator = new UniswapV3PoolCreator();
            tip(uniswapV3PoolCreator.WETH9(), address(uniswapV3PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV3PoolCreator));
            swapManager = new SwapManagerUniV3(
                address(morphoToken),
                MORPHO_UNIV3_FEE,
                REWARD_TOKEN,
                REWARD_UNIV3_FEE,
                1 hours,
                1 hours
            );
        } else if (block.chainid == Chains.AVALANCHE_MAINNET) {
            // Avalanche network.
            // Create a MORPHO / WAVAX pool.
            uniswapV2PoolCreator = new UniswapV2PoolCreator();
            tip(REWARD_TOKEN, address(uniswapV2PoolCreator), INITIAL_BALANCE * WAD);
            morphoToken = new MorphoToken(address(uniswapV2PoolCreator));
            uniswapV2PoolCreator.createPoolAndAddLiquidity(address(morphoToken));
            swapManager = new SwapManagerUniV2(
                0x60aE616a2155Ee3d9A68541Ba4544862310933d4,
                address(morphoToken),
                REWARD_TOKEN,
                1 hours
            );
        }

        matchingEngine = new MatchingEngineForAave();

        // Deploy proxy

        proxyAdmin = new ProxyAdmin();

        marketsManagerImplV1 = new MarketsManagerForAave();
        marketsManagerProxy = new TransparentUpgradeableProxy(
            address(marketsManagerImplV1),
            address(this),
            ""
        );
        marketsManagerProxy.changeAdmin(address(proxyAdmin));
        marketsManager = MarketsManagerForAave(address(marketsManagerProxy));
        marketsManager.initialize(lendingPool, interestRates);

        positionsManagerImplV1 = new PositionsManagerForAave();
        positionsManagerProxy = new TransparentUpgradeableProxy(
            address(positionsManagerImplV1),
            address(this),
            ""
        );
        positionsManagerProxy.changeAdmin(address(proxyAdmin));
        positionsManager = PositionsManagerForAave(address(positionsManagerProxy));
        positionsManager.initialize(
            marketsManager,
            matchingEngine,
            ILendingPoolAddressesProvider(lendingPoolAddressesProviderAddress),
            maxGas,
            20
        );

        if (block.chainid == Chains.ETH_MAINNET) {
            // Mainnet network
            rewardsManager = new RewardsManagerForAaveOnMainnetAndAvalanche(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager)),
                address(swapManager)
            );
            uniswapV3PoolCreator.createPoolAndMintPosition(address(morphoToken));
        } else if (block.chainid == Chains.AVALANCHE_MAINNET) {
            // Avalanche network
            rewardsManager = new RewardsManagerForAaveOnMainnetAndAvalanche(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager)),
                address(swapManager)
            );
        } else if (block.chainid == Chains.POLYGON_MAINNET) {
            // Polygon network
            rewardsManager = new RewardsManagerForAaveOnPolygon(
                lendingPool,
                IPositionsManagerForAave(address(positionsManager)),
                address(swapManager)
            );
            uniswapV3PoolCreator.createPoolAndMintPosition(address(morphoToken));
        }

        treasuryVault = new User(positionsManager);

        fakePositionsManagerImpl = new PositionsManagerForAave();

        protocolDataProvider = IProtocolDataProvider(protocolDataProviderAddress);

        oracle = IPriceOracleGetter(lendingPoolAddressesProvider.getPriceOracle());

        marketsManager.setPositionsManager(address(positionsManager));
        positionsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);

        rewardsManager.setAaveIncentivesController(aaveIncentivesControllerAddress);
        positionsManager.setTreasuryVault(address(treasuryVault));
        positionsManager.setRewardsManager(address(rewardsManager));

        createMarket(aDai);
        createMarket(aUsdc);
        createMarket(aWbtc);
        createMarket(aUsdt);
    }

    function createMarket(address _aToken) internal {
        address underlying = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        marketsManager.createMarket(underlying);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_aToken);

        hevm.label(_aToken, ERC20(_aToken).symbol());
        hevm.label(underlying, ERC20(underlying).symbol());
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(positionsManager));
            hevm.label(
                address(suppliers[i]),
                string(abi.encodePacked("Supplier", Strings.toString(i + 1)))
            );
            fillUserBalances(suppliers[i]);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(positionsManager));
            hevm.label(
                address(borrowers[i]),
                string(abi.encodePacked("Borrower", Strings.toString(i + 1)))
            );
            fillUserBalances(borrowers[i]);
        }
        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function fillUserBalances(User _user) internal {
        tip(dai, address(_user), INITIAL_BALANCE * WAD);
        tip(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(swapManager), "SwapManager");
        hevm.label(address(uniswapV3PoolCreator), "UniswapV3PoolCreator");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(aaveIncentivesControllerAddress, "AaveIncentivesController");
        hevm.label(address(lendingPoolAddressesProvider), "LendingPoolAddressesProvider");
        hevm.label(address(lendingPool), "LendingPool");
        hevm.label(address(protocolDataProvider), "ProtocolDataProvider");
        hevm.label(address(oracle), "AaveOracle");
        hevm.label(address(treasuryVault), "TreasuryVault");
        hevm.label(address(interestRates), "InterestRates");
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(positionsManager));
            fillUserBalances(borrowers[borrowers.length - 1]);

            suppliers.push(new User(positionsManager));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        hevm.store(
            address(lendingPoolAddressesProvider),
            keccak256(abi.encode(bytes32("PRICE_ORACLE"), 2)),
            bytes32(uint256(uint160(address(customOracle))))
        );

        for (uint256 i = 0; i < pools.length; i++) {
            address underlying = IAToken(pools[i]).UNDERLYING_ASSET_ADDRESS();

            customOracle.setDirectPrice(underlying, oracle.getAssetPrice(underlying));
        }

        return customOracle;
    }

    function setMaxGasHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {
        PositionsManagerForAaveStorage.MaxGas memory newMaxGas = PositionsManagerForAaveStorage
        .MaxGas({supply: _supply, borrow: _borrow, withdraw: _withdraw, repay: _repay});

        positionsManager.setMaxGas(newMaxGas);
    }

    function move1YearForward(address _marketAddress) public {
        for (uint256 k; k < 365; k++) {
            hevm.warp(block.timestamp + (1 days));
            marketsManager.updateP2PExchangeRates(_marketAddress);
        }
    }
}
